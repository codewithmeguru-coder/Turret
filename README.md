# Turret

Move songs between Spotify and YouTube, on your computer or your Android phone. Playing a public Spotify playlist on YouTube needs no API keys or logins.

## What it does

- **Spotify → YouTube:** paste a public Spotify playlist link. The app finds each song on YouTube, lets you skip wrong matches, and opens YouTube with the songs queued.
- **YouTube → Spotify:** paste YouTube video or playlist links. The app finds each song on Spotify and creates a private playlist in your account. This needs a Spotify developer app (see below).

## Web app (computer)

Requires Python 3.9+.

```bash
pip install -r requirements.txt
python app.py
```

Your browser opens at `http://127.0.0.1:8888`.

## Android app

The Flutter project is in `mobile/`. Build the installable file with:

```bash
cd mobile
flutter build apk --release
```

The APK is written to `mobile/build/app/outputs/flutter-apk/app-release.apk`. Copy it to your phone and open it to install.

## Limits

- The Spotify playlist must be public.
- YouTube's play link holds 50 videos, so longer playlists play in batches of 50.
- The Android app reads only the first 100 videos of a YouTube playlist.
- Matching uses the top search result, so a cover or live version can occasionally slip in.

## Optional: connect your Spotify account

Needed for YouTube → Spotify and for reading your live Spotify queue.

1. Create an app at <https://developer.spotify.com/dashboard> and add your Spotify account under User Management.
2. Add both redirect URIs: `http://127.0.0.1:8888/callback` (web app) and `turret://callback` (Android app).
3. **Web app:** run `pip install spotipy`, set the `SPOTIPY_CLIENT_ID` and `SPOTIPY_CLIENT_SECRET` environment variables, restart, and click Connect Spotify.
4. **Android app:** build with `flutter build apk --release --dart-define=SPOTIFY_CLIENT_ID=<your client ID>` so the ID is built in. Users then just tap the account icon and Connect Spotify. No client secret is stored on the phone.
