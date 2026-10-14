"""One bounded JSON request per process. No shell, cookies, downloads or user secrets in logs."""
import contextlib
import importlib.metadata
import io
import json
import os
import re
import sys
import zipfile
from urllib.parse import urlparse, parse_qs

sys.stdout.reconfigure(encoding='utf-8')

vendor_dir = os.path.join(os.path.dirname(__file__), 'vendor')
if os.path.isdir(vendor_dir):
    for item in os.listdir(vendor_dir):
        if item.endswith(('.zip', '.whl')):
            pkg_path = os.path.join(vendor_dir, item)
            if pkg_path not in sys.path:
                sys.path.insert(0, pkg_path)


def valid_url(value, source):
    url = urlparse(value)
    if url.scheme != 'https' or url.username or url.password or url.port:
        raise ValueError('Invalid source URL')
    hosts = {'soundcloud': {'soundcloud.com', 'www.soundcloud.com'},
             'youtube': {'www.youtube.com', 'youtube.com', 'music.youtube.com'},
             'spotify': {'open.spotify.com'}}
    if url.hostname not in hosts.get(source, set()):
        raise ValueError('Invalid source host')
    if source == 'youtube' and not parse_qs(url.query).get('v'):
        raise ValueError('Missing video ID')
    return value


class QuietLogger:
    def debug(self, *_): pass
    def warning(self, *_): pass
    def error(self, *_): pass


def package_version(name):
    # Diagnostics do not need to import the entire extraction engine. Prefer the
    # vendored copy that actually wins sys.path, not an unrelated installed dist.
    relative = {'yt-dlp': 'yt_dlp/version.py', 'yt-dlp-ejs': 'yt_dlp_ejs/_version.py'}.get(name)
    if relative:
        for entry in sys.path:
            try:
                if entry.endswith(('.zip', '.whl')):
                    with zipfile.ZipFile(entry) as archive:
                        value = archive.read(relative).decode('utf-8')
                else:
                    with open(os.path.join(entry, relative), encoding='utf-8') as file:
                        value = file.read(16384)
                match = re.search(r"^__version__\s*=\s*(?:version\s*=\s*)?['\"]([^'\"]+)['\"]", value, re.M)
                if match: return match[1]
            except (OSError, KeyError, zipfile.BadZipFile):
                continue
    try: return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError: return None


def normalized(info, source):
    return {'track_id': str(info.get('id') or ''), 'title': str(info.get('track') or info.get('title') or '')[:300],
            'artist': str(info.get('artist') or info.get('uploader') or info.get('channel') or '')[:300],
            'album': str(info.get('album') or '')[:300], 'duration': info.get('duration') or 0,
            'cover': info.get('thumbnail') or '', 'source': source,
            'source_url': info.get('webpage_url') or '', 'license': str(info.get('license') or '')[:500],
            'genres': (info.get('genres') or [])[:30], 'tags': (info.get('tags') or [])[:30],
            'availability': info.get('availability'), 'audio_url': info.get('url'),
            'codec': info.get('acodec'), 'ext': info.get('ext'), 'protocol': info.get('protocol'),
            'http_headers': {k: v for k, v in (info.get('http_headers') or {}).items() if k.lower() in {'user-agent', 'accept'}}}


def extract(request):
    from yt_dlp import YoutubeDL
    source = request['source']
    url = valid_url(request['url'], source)
    options = {'quiet': True, 'no_warnings': True, 'logger': QuietLogger(), 'noplaylist': True,
               'skip_download': True, 'cachedir': False, 'socket_timeout': 15, 'retries': 2,
               'extractor_retries': 2, 'fragment_retries': 2,
               'format': 'bestaudio[protocol=https][ext=m4a]/bestaudio[protocol=https]/bestaudio[protocol=m3u8_native]/bestaudio[protocol=m3u8]/bestaudio',
               'extract_flat': False, 'playlistend': 1, 'allow_unplayable_formats': False}
    # Let the bundled extractor select its supported clients and fallbacks.
    # Forcing five clients on every track increases network/JS work and includes
    # clients whose formats require unavailable tokens. Never fall back to video.
    if request.get('deno'):
        options['js_runtimes'] = {'deno': {'path': request['deno']}}
    elif request.get('node'):
        options['js_runtimes'] = {'node': {'path': request['node']}}
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=False)
    if not info or info.get('_type') in {'playlist', 'multi_video'}:
        raise ValueError('No single audio track')
    return normalized(info, source)


def music_search(request):
    try:
        from ytmusicapi import YTMusic
        results = YTMusic().search(str(request['query'])[:200], filter='songs', limit=min(15, request.get('limit', 10)))
        tracks = []
        for item in results[:15]:
            if not item.get('videoId'): continue
            thumbs = item.get('thumbnails') or []
            tracks.append({'track_id': item['videoId'], 'title': item.get('title') or '',
                           'artist': ', '.join(a['name'] for a in item.get('artists', []) if a.get('name')),
                           'album': (item.get('album') or {}).get('name', ''),
                           'duration': item.get('duration_seconds') or 0,
                           'cover': thumbs[-1].get('url', '') if thumbs else '', 'source': 'youtube',
                           'source_url': 'https://www.youtube.com/watch?v=' + item['videoId']})
        return tracks
    except Exception:
        from yt_dlp import YoutubeDL
        limit = min(15, request.get('limit', 10))
        query = str(request['query'])[:200]
        options = {'quiet': True, 'no_warnings': True, 'logger': QuietLogger(),
                   'extract_flat': True, 'skip_download': True, 'cachedir': False,
                   'socket_timeout': 10, 'retries': 1, 'extractor_retries': 1}
        with YoutubeDL(options) as ydl:
            res = ydl.extract_info(f"ytsearch{limit}:{query}", download=False)
        tracks = []
        for e in (res.get('entries') or []):
            if not e or not e.get('id'): continue
            thumbs = e.get('thumbnails') or []
            cover = thumbs[-1].get('url', '') if thumbs else (e.get('thumbnail') or '')
            tracks.append({'track_id': e['id'], 'title': str(e.get('title') or '')[:300],
                           'artist': str(e.get('uploader') or e.get('channel') or '')[:300],
                           'album': '', 'duration': e.get('duration') or 0,
                           'cover': cover, 'source': 'youtube',
                           'source_url': 'https://www.youtube.com/watch?v=' + e['id']})
        return tracks


def spotify_metadata(request):
    from dataclasses import asdict
    from spotdl.utils.spotify import SpotifyClient
    from spotdl.types.song import Song
    credentials = request.get('credentials') or {}
    # Official credentials, when present, travel over stdin and are never persisted.
    SpotifyClient.init(client_id=credentials.get('id', ''), client_secret=credentials.get('secret', ''),
                       no_cache=True, headless=True, max_retries=1)
    song = Song.from_url(valid_url(request['url'], 'spotify'))
    data = asdict(song)
    return {'track_id': data['song_id'], 'title': data['name'], 'artist': ', '.join(data['artists']),
            'album': data['album_name'], 'duration': data['duration'], 'cover': data.get('cover_url') or '',
            'source': 'spotify', 'source_url': data['url'], 'isrc': data.get('isrc'), 'genres': data.get('genres', [])}


def spotify_candidates(request):
    # spotDL's provider searches metadata only; no call to download() is made.
    from spotdl.providers.audio.ytmusic import YouTubeMusic
    from spotdl.providers.audio.soundcloud import SoundCloud
    from spotdl.providers.audio.youtube import YouTube
    from dataclasses import asdict, is_dataclass
    query = str(request['query'])[:200]
    found = []
    errors = []
    for name, cls in [('youtube', YouTubeMusic), ('soundcloud', SoundCloud), ('youtube', YouTube)]:
        try:
            provider = cls(output_format='m4a')
            results = provider.get_results(query)
            for item in results[:10]:
                if is_dataclass(item): item = asdict(item)
                url = item.get('url') or item.get('webpage_url') or item.get('link')
                if not url: continue
                found.append({'source': name, 'source_url': url, 'title': item.get('title') or item.get('name') or '',
                              'artist': ', '.join(item.get('artists') or []) or item.get('author') or item.get('artist') or item.get('uploader') or '',
                              'duration': item.get('duration') or 0, 'cover': item.get('thumbnail') or '',
                              'track_id': str(item.get('result_id') or item.get('id') or '')})
            if found: break
        except Exception:
            errors.append(name)
    return {'candidates': found[:10], 'failed_sources': errors}



def public_playlist(request):
    """Flat metadata only: never follows entries into audio extraction."""
    from yt_dlp import YoutubeDL
    value = str(request.get('url') or '')
    url = urlparse(value)
    if url.scheme != 'https' or url.hostname not in {'www.youtube.com', 'youtube.com', 'music.youtube.com'} or url.username or url.password or url.port:
        raise ValueError('Invalid playlist host')
    collection = parse_qs(url.query).get('list', [''])[0]
    profile = re.fullmatch(r'/(?:@[\w.%~-]{1,150}|channel/UC[\w-]{22}|user/[\w.-]{1,100})/playlists', url.path)
    if not (url.path == '/playlist' and re.fullmatch(r'[\w-]{10,150}', collection)) and not profile:
        raise ValueError('Invalid playlist URL')
    start = max(1, min(10001, int(request.get('start') or 1)))
    limit = max(1, min(101, int(request.get('limit') or 101)))
    options = {'quiet': True, 'no_warnings': True, 'logger': QuietLogger(),
               'extract_flat': True, 'skip_download': True, 'noplaylist': False,
               'playliststart': start, 'playlistend': start + limit - 1,
               'socket_timeout': 8, 'retries': 1, 'extractor_retries': 1,
               'ignoreerrors': True, 'cachedir': False}
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(value, download=False)
        if not isinstance(info, dict):
            raise ValueError('Public playlist unavailable')
        entries = list(info.get('entries') or [])[:limit]
        clean = []
        for item in entries:
            if not isinstance(item, dict): continue
            clean.append({key: item.get(key) for key in ['id', 'url', 'webpage_url', 'title', 'uploader', 'channel', 'artist', 'album', 'duration', 'thumbnails', 'playlist_count', 'availability']})
        return {'id': info.get('id'), 'title': info.get('title'), 'entries': clean,
                'playlist_count': info.get('playlist_count'), 'skipped_entries': sum(not isinstance(item, dict) for item in entries), 'thumbnails': info.get('thumbnails') or []}


def main():
    request = json.loads(sys.stdin.buffer.read(65537))
    action = request.get('action')
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        if action == 'versions':
            result = {name: package_version(name) for name in ['yt-dlp', 'yt-dlp-ejs', 'ytmusicapi', 'spotdl']}
        elif action == 'extract': result = extract(request)
        elif action == 'music-search': result = music_search(request)
        elif action == 'public-playlist': result = public_playlist(request)
        elif action == 'spotify-metadata': result = spotify_metadata(request)
        elif action == 'spotify-candidates': result = spotify_candidates(request)
        else: raise ValueError('Unsupported operation')
    sys.stdout.write(json.dumps({'ok': True, 'result': result}, ensure_ascii=False))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        # Raw upstream errors can contain signed CDN URLs and credentials.
        name = type(error).__name__
        code = 'EXTRACTOR_MODULE' if isinstance(error, (ModuleNotFoundError, ImportError)) else 'EXTRACTOR_UPSTREAM'
        sys.stdout.write(json.dumps({'ok': False, 'code': code, 'type': name}))
        sys.exit(1)
