"""Derive genuine static Nunito faces from the unchanged licensed variable file.

Build/test do not need FontTools: all generated faces are committed assets.
Regeneration uses FontTools 4.66.1; local QA tooling may live in work/qa.
"""
import hashlib
import json
from pathlib import Path
import sys

NATIVE = Path(__file__).resolve().parents[1]
ROOT = NATIVE.parents[1]
sys.path.insert(0, str(ROOT / 'work/qa/font-tooling'))
import fontTools
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

source = NATIVE / 'assets/Nunito.ttf'
font = TTFont(source, recalcTimestamp=False)
destination = NATIVE / 'assets/fonts'
destination.mkdir(exist_ok=True)
styles = {400: 'Regular', 500: 'Medium', 600: 'SemiBold',
          700: 'Bold', 800: 'ExtraBold', 900: 'Black'}
proof = {'source': 'assets/Nunito.ttf',
         'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
         'sourceWeight': font['OS/2'].usWeightClass,
         'sourceAxes': [{'tag': a.axisTag, 'minimum': a.minValue,
                         'default': a.defaultValue, 'maximum': a.maxValue}
                        for a in font['fvar'].axes],
         'fontToolsVersion': fontTools.__version__,
         'license': 'assets/licenses/Nunito-OFL.txt',
         'copyright': font['name'].getDebugName(0), 'faces': []}
source_cmap = font.getBestCmap()
for weight, style in styles.items():
    instance = instantiateVariableFont(
        font, {'wght': weight}, inplace=False, optimize=True, updateFontNames=True,
    )
    instance.recalcTimestamp = False
    # Name the actual instantiated outlines; never merely relabel ExtraLight.
    replacements = {1: 'Nunito', 2: style,
                    3: f'GlukWave Nunito static {weight}',
                    4: f'Nunito {style}', 6: f'Nunito-{style}',
                    16: 'Nunito', 17: style}
    names = instance['name']
    for name_id, value in replacements.items():
        records = [n for n in names.names if n.nameID == name_id]
        for record in records:
            names.setName(value, name_id, record.platformID,
                          record.platEncID, record.langID)
        names.setName(value, name_id, 3, 1, 0x409)
    names.names = [n for n in names.names if n.nameID != 25]
    instance['OS/2'].usWeightClass = weight
    instance['OS/2'].fsSelection &= ~((1 << 5) | (1 << 6))
    instance['OS/2'].fsSelection |= (1 << 5) if weight >= 700 else (1 << 6)
    instance['head'].macStyle = (
        instance['head'].macStyle & ~1
    ) | (1 if weight >= 700 else 0)
    assert instance.getBestCmap() == source_cmap, 'Glyph coverage changed'
    assert 'fvar' not in instance and 'gvar' not in instance
    target = destination / f'Nunito-{style}.ttf'
    instance.save(target)
    verified = TTFont(target, recalcTimestamp=False)
    assert verified['OS/2'].usWeightClass == weight
    proof['faces'].append({
        'asset': target.relative_to(NATIVE).as_posix(),
        'weight': verified['OS/2'].usWeightClass,
        'style': verified['name'].getDebugName(2),
        'family': verified['name'].getDebugName(16),
        'variable': 'fvar' in verified,
        'glyphCount': len(verified.getGlyphOrder()),
        'codepoints': len(verified.getBestCmap()),
        'sameGlyphCoverage': verified.getBestCmap() == source_cmap,
        'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    })
    verified.close()
    instance.close()
font.close()
qa = ROOT / 'work/qa'
qa.mkdir(parents=True, exist_ok=True)
(qa / 'native-font-metadata.json').write_text(
    json.dumps(proof, ensure_ascii=False, indent=2) + '\n', encoding='utf-8',
)
print(json.dumps(proof, ensure_ascii=False, indent=2))
