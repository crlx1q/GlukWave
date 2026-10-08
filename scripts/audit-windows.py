"""Verify real Windows build inputs and the delivered ZIP without controlling UI."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
from datetime import datetime, timezone

parser = argparse.ArgumentParser()
parser.add_argument('build_workspace', type=Path)
parser.add_argument('--bundle', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
bundle = args.bundle or root / 'outputs' / 'GlukWave-windows'
archive = root / 'outputs' / 'GlukWave-windows.zip'
frozen = json.loads((root / 'docs/verification/2026-10-08/native-source-freeze.json').read_text('utf-8'))


def digest(value):
    return hashlib.sha256(value).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


matched = []
for item in frozen['files']:
    original = root / 'apps/native' / item['path']
    require(original.is_file() and digest(original.read_bytes()) == item['sha256'], 'Original source changed: ' + item['path'])
    copied = args.build_workspace / item['path']
    if copied.is_file():
        require(digest(copied.read_bytes()) == item['sha256'], 'Compiled source differs: ' + item['path'])
        matched.append(item['path'])
require(len(matched) >= 50, 'Insufficient build input coverage')

binary_hashes = {}
for name in ['glukwave.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'audio_service_win_plugin.dll',
             'flutter_secure_storage_windows_plugin.dll', 'tray_manager_plugin.dll', 'window_manager_plugin.dll',
             'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']:
    value = (bundle / name).read_bytes()
    require(value[:2] == b'MZ', 'Missing PE header: ' + name)
    header = struct.unpack_from('<I', value, 60)[0]
    require(value[header:header + 4] == b'PE\0\0', 'Invalid PE signature: ' + name)
    require(struct.unpack_from('<H', value, header + 4)[0] == 0x8664, 'Non-x64 binary: ' + name)
    binary_hashes[name] = digest(value)

release = args.build_workspace / 'build/windows/x64/runner/Release'
for name in ['glukwave.exe', 'data/app.so', 'flutter_windows.dll', 'libmpv-2.dll']:
    require(digest((release / name).read_bytes()) == digest((bundle / name).read_bytes()), 'Package differs from build: ' + name)
require(b'https://wave.gluk.tech' in (bundle / 'data/app.so').read_bytes(), 'Official HTTPS server origin missing from AOT')
feature_markers = {marker: marker.encode('utf-8') in (bundle / 'data/app.so').read_bytes()
                   for marker in ['/api/diagnostics/events', '/lyrics/lrclib', 'ROOM_STATE', 'Find on LRCLIB', 'deviceVolume', '/api/auth/native-captcha', 'desktop-quick-volume']}
require(all(feature_markers.values()), 'Current diagnostics or LRCLIB import missing from AOT')

manifest = json.loads((bundle / 'data/flutter_assets/FontManifest.json').read_text('utf-8'))
font_count = 0
for family in manifest:
    if family.get('family') not in ('Nunito', 'Manrope'):
        continue
    for font in family['fonts']:
        name = font['asset']
        require(digest((bundle / 'data/flutter_assets' / name).read_bytes()) == digest((root / 'apps/native' / name).read_bytes()), 'Bundled font differs: ' + name)
        font_count += 1
require(font_count == 11, 'Missing static font faces')
require((bundle / 'licenses/MPV-LGPL-2.1.txt').is_file() or any((bundle / 'licenses').glob('*LGPL*')), 'Missing mpv notices')
with zipfile.ZipFile(archive) as package:
    require(package.testzip() is None, 'ZIP CRC failed')
    archive_files = set()
    for name in package.namelist():
        if name.endswith('/'):
            continue
        parts = Path(name).parts
        require(parts[0] == 'GlukWave' and '..' not in parts, 'Unsafe ZIP path')
        relative = Path(*parts[1:])
        require(relative.as_posix() not in archive_files, 'Duplicate ZIP path')
        archive_files.add(relative.as_posix())
        require(digest(package.read(name)) == digest((bundle / relative).read_bytes()), 'ZIP differs from delivery: ' + name)
    require(archive_files == {p.relative_to(bundle).as_posix() for p in bundle.rglob('*') if p.is_file()}, 'ZIP file set differs')

result = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'passed': True, 'bundle': str(bundle),
          'featureMarkers': feature_markers,
          'file': 'outputs/GlukWave-windows.zip', 'bytes': archive.stat().st_size,
          'sha256': digest(archive.read_bytes()), 'frozenOriginalFilesMatched': len(frozen['files']),
          'compiledSourceFilesMatched': len(matched), 'compiledSourcePaths': matched,
          'binarySha256': binary_hashes, 'packageMatchesReleaseBuild': True,
          'zipCrcAndAllFilesMatched': True, 'staticFontFaces': font_count,
          'compileDefine': 'https://wave.gluk.tech', 'buildMode': 'release',
          'authenticodeSigned': False, 'uiInteractionVerified': False, 'physicalAudioVerified': False}
proof = root / 'work/qa/windows-package-proof.json'
proof.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: v for k, v in result.items() if k not in ('compiledSourcePaths', 'binarySha256')}))
