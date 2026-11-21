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
import urllib.error
import urllib.request
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlencode, urlparse

from yt_dlp import YoutubeDL

HOST, PORT = "127.0.0.1", 8888
ROOT = Path(__file__).parent
REDIRECT_URI = f"http://{HOST}:{PORT}/callback"
SCOPES = (
    "user-read-playback-state user-read-currently-playing "
    "playlist-modify-private playlist-modify-public"
)
SPOTIFY_API = "https://api.spotify.com/v1"
# Bracketed bits of a YouTube title that are not part of the song name.
TITLE_NOISE = re.compile(
    r"\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|remaster|hd|4k|mv|live)[^\)\]]*[\)\]]",
    re.I,
)


def load_saved_keys():
    """Pick up keys saved with `setx` even if this terminal was opened before they were set."""
    if os.name != "nt":
        return
    import winreg

    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
        for name in ("SPOTIPY_CLIENT_ID", "SPOTIPY_CLIENT_SECRET"):
            if not os.environ.get(name):
                try:
                    os.environ[name] = winreg.QueryValueEx(key, name)[0]
                except OSError:
                    pass


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
        return {"id": None}
    video = entries[0]["id"]
    return {"id": video, "title": entries[0].get("title"), "url": f"https://www.youtube.com/watch?v={video}"}


# ---- YouTube -> Spotify -------------------------------------------------

def song_label(title, channel):
    """Turn a YouTube title and channel into an 'Artist - Song' search label."""
    title = TITLE_NOISE.sub("", title or "").split("|")[0].strip()
    channel = re.sub(r"\s*(- Topic|VEVO)$", "", channel or "", flags=re.I).strip()
    return title if " - " in title or not channel else f"{channel} - {title}"


def video_label(video_id):
    url = "https://www.youtube.com/oembed?format=json&url=" + quote(f"https://www.youtube.com/watch?v={video_id}")
    try:
        data = json.loads(urllib.request.urlopen(url, timeout=15).read().decode("utf-8"))
        return song_label(data.get("title"), data.get("author_name"))
    except Exception:
        return None


def playlist_url(list_id, link):
    """YouTube Mixes (RD... lists) have no playlist page; they open from a watch page instead."""
    if not list_id.startswith("RD"):
        return f"https://www.youtube.com/playlist?list={list_id}"
    video = re.search(r"(?:v=|youtu\.be/)([\w-]{11})", link)
    seed = video.group(1) if video else list_id[2:][-11:]
    return f"https://www.youtube.com/watch?v={seed}&list={list_id}"


def youtube_tracks(text):
    """Read songs from pasted YouTube links: videos, saved playlists, or this app's play link."""
    video_ids, labels = [], []
    for line in text.split():
        if "video_ids=" in line:
            video_ids += [v for v in parse_qs(urlparse(line).query).get("video_ids", [""])[0].split(",") if v]
            continue
        playlist = re.search(r"[?&]list=([\w-]+)", line)
        # Includes TL... lists: the temporary playlist YouTube makes for a watch_videos link or a share.
        if playlist:
            try:
                with YoutubeDL({"quiet": True, "no_warnings": True, "extract_flat": True, "playlistend": 100}) as ydl:
                    info = ydl.extract_info(playlist_url(playlist.group(1), line), download=False)
                found = [song_label(e.get("title"), e.get("channel") or e.get("uploader"))
                         for e in info.get("entries") or [] if e.get("title")]
                if found:
                    labels += found
                    continue
            except Exception:
                pass
        video = re.search(r"(?:v=|youtu\.be/|shorts/|embed/)([\w-]{11})", line)
        if video:
            video_ids.append(video.group(1))
    if video_ids:
        with ThreadPoolExecutor(8) as pool:
            labels += [label for label in pool.map(video_label, video_ids) if label]
    if not labels:
        raise ValueError("No YouTube videos found in what you pasted.")
    return {"name": "YouTube songs", "tracks": labels}


def spotify_request(method, path, payload=None):
    oauth = spotify_oauth()
    token = oauth and oauth.validate_token(oauth.cache_handler.get_cached_token())
    if not token:
        raise ValueError("Connect Spotify first.")
    request = urllib.request.Request(
        SPOTIFY_API + path,
        method=method,
        data=json.dumps(payload).encode("utf-8") if payload is not None else None,
        headers={"Authorization": f"Bearer {token['access_token']}", "Content-Type": "application/json"},
    )
    try:
        body = urllib.request.urlopen(request, timeout=20).read()
    except urllib.error.HTTPError as error:
        try:
            message = json.loads(error.read().decode("utf-8"))["error"]["message"]
        except Exception:
            message = error.reason
        failure = ValueError(f"Spotify said: {message} ({error.code})")
        failure.status = error.code
        raise failure
    return json.loads(body.decode("utf-8")) if body else {}


def spotify_first(method, paths, payload):
    """Spotify renamed some endpoints; try the current path, then the older one."""
    for index, path in enumerate(paths):
        try:
            return spotify_request(method, path, payload)
        except ValueError as error:
            if getattr(error, "status", None) not in (404, 405) or index == len(paths) - 1:
                raise


def spotify_search(query):
    params = urlencode({"q": query.replace(" - ", " "), "type": "track", "limit": 1})
    items = spotify_request("GET", f"/search?{params}").get("tracks", {}).get("items") or []
    if not items:
        return {"id": None}
    track = items[0]
    artists = ", ".join(a["name"] for a in track["artists"])
    return {"id": track["uri"], "title": f"{artists} - {track['name']}", "url": track["external_urls"]["spotify"]}


def spotify_create_playlist(name, uris):
    uris = [u for u in uris if isinstance(u, str) and u.startswith("spotify:track:")]
    if not uris:
        raise ValueError("There are no songs to add.")
    details = {"name": (name or "From YouTube").strip()[:100], "public": False}
    user = spotify_request("GET", "/me")["id"]
    playlist = spotify_first("POST", ["/me/playlists", f"/users/{user}/playlists"], details)
    for start in range(0, len(uris), 100):
        chunk = {"uris": uris[start:start + 100]}
        spotify_first("POST", [f"/playlists/{playlist['id']}/items", f"/playlists/{playlist['id']}/tracks"], chunk)
    return {"url": playlist["external_urls"]["spotify"], "count": len(uris)}


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
            elif url.path == "/api/spotify/search":
                self.send_json(spotify_search(query.get("q", "")))
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

    def do_POST(self):
        try:
            # Requiring JSON stops other websites from posting to this local app.
            if "application/json" not in self.headers.get("Content-Type", ""):
                return self.send_json({"error": "JSON required"}, 415)
            length = int(self.headers.get("Content-Length") or 0)
            data = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            if self.path == "/api/youtube":
                self.send_json(youtube_tracks(str(data.get("links", ""))))
            elif self.path == "/api/spotify/playlist":
                self.send_json(spotify_create_playlist(str(data.get("name", "")), data.get("uris") or []))
            else:
                self.send_json({"error": "Not found"}, 404)
        except ValueError as error:
            self.send_json({"error": str(error)}, 400)
        except Exception as error:
            self.send_json({"error": f"Something went wrong: {error}"}, 500)


if __name__ == "__main__":
    load_saved_keys()
    # On Windows the default lets a second copy share the port silently, leaving a stale one answering.
    ThreadingHTTPServer.allow_reuse_address = os.name != "nt"
    try:
        server = ThreadingHTTPServer((HOST, PORT), Handler)
    except OSError:
        sys.exit(f"Port {PORT} is already in use. Close the other copy of this app first.")
    address = f"http://{HOST}:{PORT}"
    print(f"Running at {address}  (Ctrl+C to stop)")
    if "--no-browser" not in sys.argv:
        webbrowser.open(address)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
