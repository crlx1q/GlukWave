"""One bounded JSON request per process. No shell, cookies, downloads or user secrets in logs."""
import contextlib
import importlib.metadata
import io
import json
import sys
from urllib.parse import urlparse, parse_qs

sys.stdout.reconfigure(encoding='utf-8')


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


def normalized(info, source):
    return {'track_id': str(info.get('id') or ''), 'title': str(info.get('track') or info.get('title') or '')[:300],
            'artist': str(info.get('artist') or info.get('uploader') or info.get('channel') or '')[:300],
            'album': str(info.get('album') or '')[:300], 'duration': info.get('duration') or 0,
            'cover': info.get('thumbnail') or '', 'source': source,
            'source_url': info.get('webpage_url') or '', 'license': str(info.get('license') or '')[:500],
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
               'format': 'bestaudio[protocol=https][ext=m4a]/bestaudio[protocol=https]/bestaudio[protocol=m3u8_native]/bestaudio[protocol=m3u8]/bestaudio/best',
               'extract_flat': False, 'playlistend': 1, 'allow_unplayable_formats': False,
               'nocheckcertificate': True}
    if source == 'youtube':
        options['extractor_args'] = {
            'youtube': {
                'player_client': ['android', 'ios', 'mweb', 'web', 'tv']
            }
        }
    if request.get('deno'):
        options['js_runtimes'] = {'deno': {'path': request['deno']}}
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=False)
    if not info or info.get('_type') in {'playlist', 'multi_video'}:
        raise ValueError('No single audio track')
    return normalized(info, source)


def music_search(request):
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


def main():
    request = json.loads(sys.stdin.buffer.read(65537))
    action = request.get('action')
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        if action == 'versions':
            result = {}
            for name in ['yt-dlp', 'yt-dlp-ejs', 'ytmusicapi', 'spotdl']:
                try: result[name] = importlib.metadata.version(name)
                except importlib.metadata.PackageNotFoundError: result[name] = None
        elif action == 'extract': result = extract(request)
        elif action == 'music-search': result = music_search(request)
        elif action == 'spotify-metadata': result = spotify_metadata(request)
        elif action == 'spotify-candidates': result = spotify_candidates(request)
        else: raise ValueError('Unsupported operation')
    sys.stdout.write(json.dumps({'ok': True, 'result': result}, ensure_ascii=False))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        # Raw upstream errors can contain signed CDN URLs and credentials.
        name = type(error).__name__
        msg = str(error)[:300]
        sys.stdout.write(json.dumps({'ok': False, 'code': 'EXTRACTOR_UPSTREAM', 'type': name, 'message': msg}))
        sys.exit(1)
