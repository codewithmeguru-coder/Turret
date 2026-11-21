// Live check of the parts that need no Spotify account.
// Run from the mobile folder:  dart run tool/check.dart
import 'package:spotify_youtube/spotify.dart';
import 'package:spotify_youtube/youtube.dart';

Future<void> main() async {
  final tracks = await spotifyPlaylistTracks('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=x');
  print('Spotify playlist: ${tracks.length} tracks, first: ${tracks.first}');

  final youtube = YoutubeService();
  final found = await youtube.search(tracks.first);
  print('YouTube match: ${found?.title} (${found?.id})');

  final labels = await youtube.tracksFromLinks(
    'https://www.youtube.com/watch_videos?video_ids=dQw4w9WgXcQ,DLV8FpyxZPQ\n'
    'https://www.youtube.com/playlist?list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj',
  );
  print('YouTube links: ${labels.length} songs, first: ${labels.take(3).join(' | ')}');
}
