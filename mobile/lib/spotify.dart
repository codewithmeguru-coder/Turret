import 'dart:convert';

import 'package:http/http.dart' as http;

/// An error with a message that is safe to show to the user.
class AppError implements Exception {
  AppError(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// A song found on the destination service.
class Found {
  const Found(this.id, this.title, this.url);
  final String id; // YouTube video id or Spotify track URI
  final String title;
  final String url;
}

/// Follows Spotify's short share links (spotify.link/...) to the real address.
Future<String> _expandShortLink(String link) async {
  var current = link;
  final client = http.Client();
  try {
    for (var hop = 0; hop < 5 && !current.contains('/playlist/'); hop++) {
      final request = http.Request('GET', Uri.parse(current))
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0';
      final response = await client.send(request);
      await response.stream.drain<void>();
      final next = response.headers['location'];
      if (next == null) break;
      current = Uri.parse(current).resolve(next).toString();
    }
  } catch (_) {
    // Fall through with whatever we have.
  } finally {
    client.close();
  }
  return current;
}

/// Reads the songs of a public Spotify playlist. Needs no login.
Future<List<String>> spotifyPlaylistTracks(String link) async {
  link = link.trim();
  final shortLink = RegExp(r'https?://\S*spotify\S*link/\S+').firstMatch(link);
  if (!link.contains('playlist') && shortLink != null) {
    link = await _expandShortLink(shortLink.group(0)!);
  }
  final id = RegExp(r'playlist[/:]([A-Za-z0-9]+)').firstMatch(link)?.group(1);
  if (id == null) throw AppError('That does not look like a Spotify playlist link.');
  try {
    final response = await http.get(
      Uri.parse('https://open.spotify.com/embed/playlist/$id'),
      headers: {'User-Agent': 'Mozilla/5.0'},
    );
    final html = utf8.decode(response.bodyBytes);
    final data = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true)
        .firstMatch(html)!
        .group(1)!;
    final tracks = jsonDecode(data)['props']['pageProps']['state']['data']['entity']['trackList'] as List;
    return [
      for (final track in tracks)
        '${(track['subtitle'] as String).replaceAll(' ', ' ')} - ${track['title']}',
    ];
  } catch (_) {
    throw AppError('Could not read the playlist. Make sure it is public.');
  }
}

/// Calls to Spotify that need the user's account.
class SpotifyApi {
  SpotifyApi(this._token);
  final Future<String> Function() _token;
  static const _base = 'https://api.spotify.com/v1';

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final request = http.Request(method, Uri.parse('$_base$path'))
      ..headers['Authorization'] = 'Bearer ${await _token()}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await request.send());
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) {
      var message = 'error ${response.statusCode}';
      try {
        message = jsonDecode(text)['error']['message'] as String;
      } catch (_) {}
      throw AppError('Spotify said: $message', response.statusCode);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// Spotify renamed some endpoints; try the current path, then the older one.
  Future<dynamic> _sendFirst(String method, List<String> paths, Object body) async {
    for (var i = 0; ; i++) {
      try {
        return await _send(method, paths[i], body);
      } on AppError catch (error) {
        if ((error.status != 404 && error.status != 405) || i == paths.length - 1) rethrow;
      }
    }
  }

  Future<Found?> search(String query) async {
    final q = Uri.encodeQueryComponent(query.replaceAll(' - ', ' '));
    final items = (await _send('GET', '/search?q=$q&type=track&limit=1'))['tracks']['items'] as List;
    if (items.isEmpty) return null;
    final track = items.first;
    final artists = (track['artists'] as List).map((a) => a['name']).join(', ');
    return Found(track['uri'] as String, '$artists - ${track['name']}', track['external_urls']['spotify'] as String);
  }

  /// The song playing now followed by what is queued after it.
  Future<List<String>> queue() async {
    final data = await _send('GET', '/me/player/queue');
    final tracks = [
      if (data?['currently_playing'] != null) data['currently_playing'],
      ...(data?['queue'] as List? ?? const []),
    ];
    final labels = [
      for (final track in tracks)
        if (track['artists'] != null)
          '${(track['artists'] as List).map((a) => a['name']).join(', ')} - ${track['name']}',
    ];
    if (labels.isEmpty) throw AppError('Your queue is empty. Spotify must be playing something.');
    return labels;
  }

  /// Creates a private playlist and returns its link.
  Future<String> createPlaylist(String name, List<String> uris) async {
    if (uris.isEmpty) throw AppError('There are no songs to add.');
    final details = {'name': name.trim().isEmpty ? 'From YouTube' : name.trim(), 'public': false};
    final user = (await _send('GET', '/me'))['id'];
    final playlist = await _sendFirst('POST', ['/me/playlists', '/users/$user/playlists'], details);
    final id = playlist['id'];
    for (var start = 0; start < uris.length; start += 100) {
      final end = start + 100 > uris.length ? uris.length : start + 100;
      await _sendFirst('POST', ['/playlists/$id/items', '/playlists/$id/tracks'], {'uris': uris.sublist(start, end)});
    }
    return playlist['external_urls']['spotify'] as String;
  }
}
