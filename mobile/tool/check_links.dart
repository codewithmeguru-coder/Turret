// Live check that shared YouTube Mix and temporary playlist links are read.
// Run from the mobile folder:  dart run tool/check_links.dart
import 'package:spotify_youtube/youtube.dart';

Future<void> main() async {
  final youtube = YoutubeService();
  for (final link in [
    'https://youtube.com/playlist?list=RDTR3Vdo5etCQ&playnext=1&si=iaoTdkt0onhc6ZNq',
    'https://www.youtube.com/watch_videos?video_ids=dQw4w9WgXcQ,9bZkp7q19f0',
  ]) {
    final labels = await youtube.tracksFromLinks(link);
    print('${labels.length} songs, first: ${labels.take(2).join(' | ')}');
  }
}
