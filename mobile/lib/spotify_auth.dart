import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'spotify.dart';

/// Signs the user in to Spotify (PKCE, so no client secret lives on the phone)
/// and keeps the sign-in between launches.
class SpotifyAuth {
  static const callbackScheme = 'turret';
  static const redirectUri = '$callbackScheme://callback';

  /// The Spotify app's client ID, baked in at build time with
  /// --dart-define=SPOTIFY_CLIENT_ID=... so users never have to enter one.
  /// A client ID is public (it appears in the sign-in address); there is no secret here.
  static const builtInClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const _scopes = 'user-read-playback-state user-read-currently-playing '
      'playlist-modify-private playlist-modify-public';

  String clientId = '';
  String? _accessToken;
  String? _refreshToken;
  DateTime _expires = DateTime(0);

  bool get connected => _refreshToken != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    clientId = builtInClientId.isNotEmpty ? builtInClientId : prefs.getString('clientId') ?? '';
    _refreshToken = prefs.getString('refreshToken');
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('clientId', clientId);
    if (_refreshToken == null) {
      await prefs.remove('refreshToken');
    } else {
      await prefs.setString('refreshToken', _refreshToken!);
    }
  }

  String _random(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> connect(String newClientId) async {
    clientId = newClientId.trim();
    if (clientId.isEmpty) throw AppError('Enter your Spotify client ID first.');
    final verifier = _random(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _random(16);
    final url = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': _scopes,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
    });
    final result = Uri.parse(
      await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: callbackScheme),
    );
    final code = result.queryParameters['code'];
    if (code == null || result.queryParameters['state'] != state) {
      throw AppError('Spotify sign-in did not complete.');
    }
    await _requestToken({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    });
  }

  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    await _save();
  }

  Future<void> _requestToken(Map<String, String> form) async {
    final response = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      body: {...form, 'client_id': clientId},
    );
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      if (form['grant_type'] == 'refresh_token') await disconnect();
      throw AppError('Spotify sign-in failed: ${data['error_description'] ?? data['error']}');
    }
    _accessToken = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String? ?? _refreshToken;
    _expires = DateTime.now().add(Duration(seconds: (data['expires_in'] as int) - 60));
    await _save();
  }

  /// A valid access token, refreshed when needed.
  Future<String> token() async {
    if (_refreshToken == null) throw AppError('Connect Spotify first.');
    if (_accessToken == null || DateTime.now().isAfter(_expires)) {
      await _requestToken({'grant_type': 'refresh_token', 'refresh_token': _refreshToken!});
    }
    return _accessToken!;
  }
}
