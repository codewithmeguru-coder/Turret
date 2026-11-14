"""Spotify -> YouTube: a small local web app.

Run:   python app.py        (opens http://127.0.0.1:8888 in your browser)

Playlists need no login (the playlist must be public).
Queue access is optional and needs a Spotify developer app: set
SPOTIPY_CLIENT_ID and SPOTIPY_CLIENT_SECRET, and add the redirect URI
http://127.0.0.1:8888/callback to the app.
"""
import json
import os
import re
import sys
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from yt_dlp import YoutubeDL

HOST, PORT = "127.0.0.1", 8888
ROOT = Path(__file__).parent
REDIRECT_URI = f"http://{HOST}:{PORT}/callback"
SCOPES = "user-read-playback-state user-read-currently-playing"


def playlist_tracks(link):
    match = re.search(r"playlist[/:]([A-Za-z0-9]+)", link) or re.fullmatch(r"([A-Za-z0-9]+)", link.strip())
    if not match:
        raise ValueError("That does not look like a Spotify playlist link.")
    request = urllib.request.Request(
        f"https://open.spotify.com/embed/playlist/{match.group(1)}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    try:
        html = urllib.request.urlopen(request, timeout=20).read().decode("utf-8")
        data = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
        entity = json.loads(data.group(1))["props"]["pageProps"]["state"]["data"]["entity"]
        tracks = entity["trackList"]
    except Exception:
        raise ValueError("Could not read the playlist. Make sure it is public (Spotify: ... > Make public).")
    return {
        "name": entity.get("name", "Playlist"),
        "tracks": [f"{t['subtitle'].replace(chr(160), ' ')} - {t['title']}" for t in tracks],
    }


def spotify_oauth():
    if not (os.environ.get("SPOTIPY_CLIENT_ID") and os.environ.get("SPOTIPY_CLIENT_SECRET")):
        return None
    from spotipy.oauth2 import SpotifyOAuth

    return SpotifyOAuth(
        redirect_uri=REDIRECT_URI,
        scope=SCOPES,
        cache_path=str(ROOT / ".spotify_token"),
        open_browser=False,
    )


def spotify_connected(oauth):
    try:
        return bool(oauth and oauth.validate_token(oauth.cache_handler.get_cached_token()))
    except Exception:
        return False


def queue_tracks():
    oauth = spotify_oauth()
    if not spotify_connected(oauth):
        raise ValueError("Connect Spotify first.")
    import spotipy

    queue = spotipy.Spotify(auth_manager=oauth).queue() or {}
    current = queue.get("currently_playing")
    tracks = [
        f"{', '.join(a['name'] for a in t['artists'])} - {t['name']}"
        for t in ([current] if current else []) + queue.get("queue", [])
        if t.get("artists")
    ]
    if not tracks:
        raise ValueError("Your queue is empty. Spotify must be playing something.")
    return {"name": "Spotify queue", "tracks": tracks}


def youtube_search(query):
    with YoutubeDL({"quiet": True, "no_warnings": True, "extract_flat": True}) as ydl:
        entries = ydl.extract_info(f"ytsearch1:{query}", download=False).get("entries") or []
    if not entries:
        return {"id": None, "title": None}
    return {"id": entries[0]["id"], "title": entries[0].get("title")}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def redirect(self, location):
        self.send_response(302)
        self.send_header("Location", location)
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            if url.path == "/":
                body = (ROOT / "index.html").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif url.path == "/api/status":
                oauth = spotify_oauth()
                self.send_json({"configured": oauth is not None, "connected": spotify_connected(oauth)})
            elif url.path == "/api/playlist":
                self.send_json(playlist_tracks(query.get("url", "")))
            elif url.path == "/api/queue":
                self.send_json(queue_tracks())
            elif url.path == "/api/search":
                self.send_json(youtube_search(query.get("q", "")))
            elif url.path == "/login":
                oauth = spotify_oauth()
                self.redirect(oauth.get_authorize_url() if oauth else "/")
            elif url.path == "/callback":
                oauth = spotify_oauth()
                if oauth and query.get("code"):
                    oauth.get_access_token(query["code"], as_dict=False, check_cache=False)
                self.redirect("/")
            else:
                self.send_json({"error": "Not found"}, 404)
        except ValueError as error:
            self.send_json({"error": str(error)}, 400)
        except Exception as error:
            self.send_json({"error": f"Something went wrong: {error}"}, 500)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    address = f"http://{HOST}:{PORT}"
    print(f"Running at {address}  (Ctrl+C to stop)")
    if "--no-browser" not in sys.argv:
        webbrowser.open(address)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
