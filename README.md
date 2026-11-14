# Spotify to YouTube

A local web app that turns a public Spotify playlist into an autoplaying YouTube session. No API keys or logins needed.

## How it works

1. Paste a public Spotify playlist link.
2. The app reads the track list from Spotify's public embed page and finds each song on YouTube with `yt-dlp`.
3. Check the matches, skip any you don't want, and press Play. YouTube opens with the songs queued.

## Run it

Requires Python 3.9+.

```bash
pip install -r requirements.txt
python app.py
```

Your browser opens at `http://127.0.0.1:8888`.

## Limits

- The playlist must be public.
- YouTube's playlist link holds 50 videos, so longer playlists play in batches of 50.
- Matching uses the top YouTube search result, so a cover or live version can occasionally slip in.

## Optional: read your Spotify queue

Reading the live queue needs a Spotify developer app. This path is implemented but untested.

1. Create an app at <https://developer.spotify.com/dashboard> with the redirect URI `http://127.0.0.1:8888/callback`.
2. Run `pip install spotipy`.
3. Set the `SPOTIPY_CLIENT_ID` and `SPOTIPY_CLIENT_SECRET` environment variables, then restart the app.

Without a developer app, add your queue to a playlist in Spotify and paste that playlist's link instead.
