import 'dart:convert';

import 'package:http/http.dart' as http;

import 'spotify.dart';

/// Bracketed bits of a YouTube title that are not part of the song name.
final _titleNoise = RegExp(
  r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|remaster|hd|4k|mv|live)[^\)\]]*[\)\]]',
  caseSensitive: false,
);

/// Turns a YouTube title and channel into an "Artist - Song" search label.
String songLabel(String title, String channel) {
  title = title.replaceAll(_titleNoise, '').split('|').first.trim();
  channel = channel.replaceAll(RegExp(r'\s*(- Topic|VEVO)$', caseSensitive: false), '').trim();
  return title.contains(' - ') || channel.isEmpty ? title : '$channel - $title';
}

/// The link that plays up to 50 videos back to back on YouTube.
String youtubePlayLink(List<String> videoIds) =>
    'https://www.youtube.com/watch_videos?video_ids=${videoIds.join(',')}';

class YoutubeService {
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
    'Accept-Language': 'en',
    'Cookie': 'SOCS=CAI', // skips the cookie-consent page in some regions
  };

  static final _firstVideo = RegExp(
    r'"videoRenderer":\{"videoId":"([\w-]{11})".*?"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"',
    dotAll: true,
  );

  /// The top video for a search, read from YouTube's results page (no API key).
  Future<Found?> search(String query) async {
    final response = await http.get(
      // sp=EgIQAQ== limits results to videos.
      Uri.https('www.youtube.com', '/results', {'search_query': query, 'sp': 'EgIQAQ=='}),
      headers: _headers,
    );
    final match = _firstVideo.firstMatch(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (match == null) return null;
    final id = match.group(1)!;
    var title = id;
    try {
      title = jsonDecode('"${match.group(2)}"') as String;
    } catch (_) {}
    return Found(id, title, 'https://www.youtube.com/watch?v=$id');
  }

  Future<String?> _videoLabel(String videoId) async {
    try {
      final target = Uri.encodeQueryComponent('https://www.youtube.com/watch?v=$videoId');
      final response = await http.get(Uri.parse('https://www.youtube.com/oembed?format=json&url=$target'));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return songLabel(data['title'] as String, data['author_name'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// The songs of a saved YouTube playlist, read from its page (first 100 videos).
  /// YouTube Mixes (RD... lists) have no playlist page, so they are read from a watch page.
  Future<List<String>> _playlistLabels(String playlistId, String link) async {
    final labels = <String>[];
    final mixLabels = <String>[]; // a watch page's queue; its side videos are only suggestions
    try {
      Uri page = Uri.https('www.youtube.com', '/playlist', {'list': playlistId});
      if (playlistId.startsWith('RD')) {
        final rest = playlistId.substring(2);
        final seed = RegExp(r'(?:v=|youtu\.be/)([\w-]{11})').firstMatch(link)?.group(1) ??
            rest.substring(rest.length > 11 ? rest.length - 11 : 0);
        page = Uri.https('www.youtube.com', '/watch', {'v': seed, 'list': playlistId});
      }
      final response = await http.get(page, headers: _headers);
      final data = RegExp(r'var ytInitialData = (\{.*?\});</script>', dotAll: true)
          .firstMatch(utf8.decode(response.bodyBytes, allowMalformed: true))!
          .group(1)!;
      void walk(Object? node) {
        if (node is List) {
          node.forEach(walk);
        } else if (node is Map) {
          final panel = node['playlistPanelVideoRenderer'];
          if (panel is Map) {
            final t = panel['title'];
            final title = t?['simpleText'] ?? (t?['runs'] as List?)?.first['text'];
            final by = (panel['shortBylineText']?['runs'] as List?)?.first['text'];
            if (title is String) mixLabels.add(songLabel(title, by is String ? by : ''));
            return;
          }
          final video = node['lockupViewModel'];
          if (video is Map && video['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
            final meta = video['metadata']?['lockupMetadataViewModel'];
            final title = meta?['title']?['content'];
            final rows = meta?['metadata']?['contentMetadataViewModel']?['metadataRows'] as List?;
            final parts = rows == null || rows.isEmpty ? null : rows.first['metadataParts'] as List?;
            final channel = parts == null || parts.isEmpty ? null : parts.first['text']?['content'];
            if (title is String) labels.add(songLabel(title, channel is String ? channel : ''));
          } else {
            node.values.forEach(walk);
          }
        }
      }

      walk(jsonDecode(data));
    } catch (_) {
      // An unreadable playlist just yields no songs.
    }
    return mixLabels.isNotEmpty ? mixLabels : labels;
  }

  /// Reads songs from pasted YouTube links: videos, saved playlists, or this app's play link.
  Future<List<String>> tracksFromLinks(String text) async {
    final labels = <String>[];
    final videoIds = <String>[];
    for (final line in text.split(RegExp(r'\s+'))) {
      if (line.contains('video_ids=')) {
        final ids = Uri.tryParse(line)?.queryParameters['video_ids'] ?? '';
        videoIds.addAll(ids.split(',').where((id) => id.isNotEmpty));
        continue;
      }
      final playlist = RegExp(r'[?&]list=([\w-]+)').firstMatch(line)?.group(1);
      // Includes TL... lists: the temporary playlist YouTube makes for a watch_videos link or a share.
      if (playlist != null) {
        final fromPlaylist = await _playlistLabels(playlist, line);
        if (fromPlaylist.isNotEmpty) {
          labels.addAll(fromPlaylist);
          continue;
        }
      }
      final video = RegExp(r'(?:v=|youtu\.be/|shorts/|embed/)([\w-]{11})').firstMatch(line)?.group(1);
      if (video != null) videoIds.add(video);
    }
    final fromVideos = await Future.wait(videoIds.map(_videoLabel));
    labels.addAll(fromVideos.whereType<String>());
    if (labels.isEmpty) throw AppError('No YouTube videos found in what you pasted.');
    return labels;
  }
}
