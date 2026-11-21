"""Play a Spotify playlist (or your current Spotify queue) on YouTube.

Usage:
    python spotify_to_youtube.py                  (asks for the playlist link)
    python spotify_to_youtube.py <playlist link>
    python spotify_to_youtube.py queue            (needs a Spotify developer app)

Playlists need no login, but the playlist must be public.
"""
import json
import re
import sys
import urllib.request
import webbrowser

from yt_dlp import YoutubeDL

CHUNK = 50  # YouTube's watch_videos link takes at most 50 videos


def playlist_tracks(link):
    match = re.search(r"playlist[/:]([A-Za-z0-9]+)", link) or re.fullmatch(r"([A-Za-z0-9]+)", link.strip())
    if not match:
        sys.exit("That does not look like a Spotify playlist link.")
    request = urllib.request.Request(
        f"https://open.spotify.com/embed/playlist/{match.group(1)}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    html = urllib.request.urlopen(request).read().decode("utf-8")
    data = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    try:
        entity = json.loads(data.group(1))["props"]["pageProps"]["state"]["data"]["entity"]
        tracks = entity["trackList"]
    except (AttributeError, KeyError, TypeError):
        sys.exit("Could not read the playlist. Make sure it is public (Spotify: ... > Make public).")
    print(f"Playlist: {entity.get('name', '?')} ({len(tracks)} tracks)")
    return [f"{t['subtitle'].replace(chr(160), ' ')} - {t['title']}" for t in tracks]


def queue_tracks():
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth

    sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
        redirect_uri="http://127.0.0.1:8888/callback",
        scope="user-read-playback-state user-read-currently-playing",
    ))
    queue = sp.queue()
    current = queue.get("currently_playing")
    return [
        f"{', '.join(a['name'] for a in t['artists'])} - {t['name']}"
        for t in ([current] if current else []) + queue.get("queue", [])
        if t.get("artists")
    ]


def youtube_id(ydl, query):
    entries = ydl.extract_info(f"ytsearch1:{query}", download=False).get("entries") or []
    return entries[0]["id"] if entries else None


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else input("Paste the Spotify playlist link: ").strip()
    tracks = queue_tracks() if source.lower() == "queue" else playlist_tracks(source)
    if not tracks:
        sys.exit("No tracks found.")

    ids = []
    with YoutubeDL({"quiet": True, "no_warnings": True, "extract_flat": True}) as ydl:
        for n, query in enumerate(tracks, 1):
            try:
                video = youtube_id(ydl, query)
            except Exception:
                video = None
            print(f"[{n}/{len(tracks)}] {query} -> {video or 'NOT FOUND'}")
            if video:
                ids.append(video)

    urls = [
        "https://www.youtube.com/watch_videos?video_ids=" + ",".join(ids[i:i + CHUNK])
        for i in range(0, len(ids), CHUNK)
    ]
    if not urls:
        sys.exit("Nothing matched on YouTube.")
    if "--no-open" not in sys.argv:
        webbrowser.open(urls[0])
    print("\nYouTube link(s):")
    print("\n".join(urls))


if __name__ == "__main__":
    main()
