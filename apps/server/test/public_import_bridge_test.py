"""Exercise the actual bridge with a fake yt-dlp engine; never downloads media."""
from pathlib import Path
import runpy
import sys
import types
import unittest

options = []


class Engine:
    def __init__(self, value):
        options.append(value)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def extract_info(self, url, download):
        assert not download
        return {'id': 'list', 'title': 'Public', 'playlist_count': 2,
                'entries': iter([{'id': 'abcdefghijk', 'title': 'Original',
                                  'formats': [{'url': 'must-not-leak'}]}, None])}


sys.modules['yt_dlp'] = types.SimpleNamespace(YoutubeDL=Engine)
bridge = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'extractors/bridge.py'),
                        run_name='public_import_bridge_test')


class PublicBridgeTests(unittest.TestCase):
    def test_flat_metadata_pagination_without_audio(self):
        value = bridge['public_playlist']({'url': 'https://www.youtube.com/playlist?list=PLabcdefghijk',
                                           'start': 101, 'limit': 101})
        self.assertTrue(options[-1]['extract_flat'])
        self.assertTrue(options[-1]['skip_download'])
        self.assertFalse(options[-1]['noplaylist'])
        self.assertEqual(options[-1]['playliststart'], 101)
        self.assertEqual(options[-1]['playlistend'], 201)
        self.assertEqual(value['skipped_entries'], 1)
        self.assertNotIn('formats', value['entries'][0])

    def test_provider_path_validation_before_extract(self):
        before = len(options)
        for value in ['https://127.0.0.1/playlist?list=PLabcdefghijk',
                      'https://www.youtube.com.evil.test/playlist?list=PLabcdefghijk',
                      'https://www.youtube.com/watch?v=abcdefghijk',
                      'https://name@www.youtube.com/playlist?list=PLabcdefghijk']:
            with self.assertRaises(ValueError):
                bridge['public_playlist']({'url': value})
        self.assertEqual(len(options), before)
        bridge['public_playlist']({'url': 'https://www.youtube.com/@%D0%94%D0%BE%D1%80%D0%B0/playlists'})


if __name__ == '__main__':
    unittest.main()
