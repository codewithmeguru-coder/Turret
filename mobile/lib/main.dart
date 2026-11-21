import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'spotify.dart';
import 'spotify_auth.dart';
import 'youtube.dart';

void main() => runApp(const App());

/// Where the songs are going.
enum Target { youtube, spotify }

class SongRow {
  SongRow(this.query);
  final String query;
  Found? found;
  String? problem;
  bool done = false;
  bool skipped = false;
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Turret',
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _chunk = 50; // YouTube's link takes at most 50 videos
  static const _parallel = 4; // searches running at once

  final _auth = SpotifyAuth();
  late final _spotify = SpotifyApi(_auth.token);
  final _youtube = YoutubeService();
  final _input = TextEditingController();
  final _playlistName = TextEditingController(text: 'From YouTube');

  Target _target = Target.youtube;
  List<SongRow> _rows = [];
  bool _busy = false;
  bool _creating = false;
  String? _error;
  String? _createdUrl;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _auth.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _playlistName.dispose();
    super.dispose();
  }

  String _message(Object error) => error is AppError ? error.message : 'Something went wrong: $error';

  List<String> get _readyIds => [
        for (final row in _rows)
          if (row.found != null && !row.skipped) row.found!.id,
      ];

  void _setTarget(Target target) {
    _run++;
    setState(() {
      _target = target;
      _rows = [];
      _busy = false;
      _error = null;
      _createdUrl = null;
      _input.clear();
    });
  }

  Future<void> _start(Future<List<String>> Function() load) async {
    final mine = ++_run;
    final target = _target;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _createdUrl = null;
      _rows = [];
    });
    try {
      final rows = [for (final track in await load()) SongRow(track)];
      if (mine != _run) return;
      setState(() => _rows = rows);
      var next = 0;
      Future<void> worker() async {
        while (next < rows.length && mine == _run) {
          final row = rows[next++];
          try {
            row.found = target == Target.youtube
                ? await _youtube.search(row.query)
                : await _spotify.search(row.query);
          } catch (error) {
            row.problem = _message(error);
          }
          row.done = true;
          if (mine == _run && mounted) setState(() {});
        }
      }

      await Future.wait(List.generate(_parallel, (_) => worker()));
    } catch (error) {
      if (mine == _run && mounted) setState(() => _error = _message(error));
    } finally {
      if (mine == _run && mounted) setState(() => _busy = false);
    }
  }

  void _find() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _error = _target == Target.youtube
          ? 'Paste a Spotify playlist link first.'
          : 'Paste at least one YouTube link first.');
      return;
    }
    _start(() => _target == Target.youtube ? spotifyPlaylistTracks(text) : _youtube.tracksFromLinks(text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _input.text = text;
    if (_target == Target.youtube || _auth.connected) _find();
  }

  Future<void> _open(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) setState(() => _error = 'Could not open $url');
  }

  Future<void> _createPlaylist() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final url = await _spotify.createPlaylist(_playlistName.text, _readyIds);
      if (mounted) setState(() => _createdUrl = url);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showSettings() async {
    final clientId = TextEditingController(text: _auth.clientId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Future<void> run(Future<void> Function() action) async {
            String? problem;
            try {
              await action();
            } catch (error) {
              problem = _message(error);
            }
            if (mounted) setState(() {});
            if (!sheetContext.mounted) return;
            if (problem == null && _auth.connected) {
              Navigator.pop(sheetContext);
            } else {
              setSheet(() {});
              if (problem != null) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(problem)));
              }
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spotify account', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Only needed to read your queue or to create Spotify playlists. '
                  'Playing a public playlist on YouTube needs no account.',
                ),
                const SizedBox(height: 16),
                if (_auth.connected) ...[
                  const Row(children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Spotify is connected'),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => run(_auth.disconnect), child: const Text('Disconnect')),
                ] else if (SpotifyAuth.builtInClientId.isNotEmpty) ...[
                  FilledButton(
                    onPressed: () => run(() => _auth.connect(SpotifyAuth.builtInClientId)),
                    child: const Text('Connect Spotify'),
                  ),
                ] else ...[
                  const Text('1. In your Spotify developer app, add this redirect URI and save:'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const SelectableText(SpotifyAuth.redirectUri),
                    trailing: IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () => Clipboard.setData(const ClipboardData(text: SpotifyAuth.redirectUri)),
                    ),
                  ),
                  const Text('2. Paste the app\'s client ID:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: clientId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Client ID'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => run(() => _auth.connect(clientId.text)),
                    child: const Text('Connect Spotify'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toYoutube = _target == Target.youtube;
    final scheme = ColorScheme.fromSeed(
      seedColor: toYoutube ? const Color(0xFFFF4B4B) : const Color(0xFF1DB954),
      brightness: MediaQuery.platformBrightnessOf(context),
    );
    final done = _rows.where((row) => row.done).length;
    final finished = _rows.isNotEmpty && done == _rows.length;
    final ids = _readyIds;
    final needsSpotify = !toYoutube && !_auth.connected;

    return Theme(
      data: ThemeData(colorScheme: scheme, useMaterial3: true),
      child: Builder(builder: (context) {
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Turret'),
            actions: [
              IconButton(
                tooltip: 'Spotify account',
                icon: Icon(_auth.connected ? Icons.account_circle : Icons.account_circle_outlined),
                onPressed: _showSettings,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SegmentedButton<Target>(
                segments: const [
                  ButtonSegment(value: Target.youtube, label: Text('Spotify → YouTube')),
                  ButtonSegment(value: Target.spotify, label: Text('YouTube → Spotify')),
                ],
                selected: {_target},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => _setTarget(selection.first),
              ),
              const SizedBox(height: 16),
              _StepTitle(1, toYoutube ? 'Paste your Spotify playlist link' : 'Paste your YouTube links'),
              const SizedBox(height: 8),
              TextField(
                controller: _input,
                minLines: toYoutube ? 1 : 3,
                maxLines: toYoutube ? 1 : 6,
                keyboardType: toYoutube ? TextInputType.url : TextInputType.multiline,
                onSubmitted: toYoutube ? (_) => _find() : null,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: toYoutube ? 'https://open.spotify.com/playlist/...' : 'One link per line: videos or a saved playlist',
                  suffixIcon: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste), onPressed: _paste),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                toYoutube
                    ? 'In Spotify: open the playlist, tap ⋯, Share, Copy link. The playlist must be public.'
                    : 'The songs go into a new private playlist in your Spotify account.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy || needsSpotify ? null : _find,
                    child: Text(toYoutube ? 'Find on YouTube' : 'Find on Spotify'),
                  ),
                  if (toYoutube && _auth.connected)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _start(_spotify.queue),
                      child: const Text('Use my queue'),
                    ),
                  if (needsSpotify)
                    OutlinedButton(onPressed: _showSettings, child: const Text('Connect Spotify first')),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              if (_busy && _rows.isEmpty) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _StepTitle(2, finished ? 'Check the matches' : 'Finding your songs…')),
                    Text(
                      finished ? '${ids.length} of ${_rows.length} matched' : '$done / ${_rows.length}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!finished) LinearProgressIndicator(value: done / _rows.length),
                if (finished) Text('Tap a match to preview it. Skip any song you don\'t want.', style: text.bodySmall),
                for (final (index, row) in _rows.indexed) _songTile(index, row, scheme),
              ],
            ],
          ),
          bottomNavigationBar: !finished || ids.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
                    child: toYoutube ? _playBar(ids) : _createBar(ids),
                  ),
                ),
        );
      }),
    );
  }

  Widget _songTile(int index, SongRow row, ColorScheme scheme) {
    final found = row.found;
    final faded = row.skipped ? scheme.onSurface.withValues(alpha: 0.4) : null;
    final strike = row.skipped ? TextDecoration.lineThrough : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: SizedBox(width: 24, child: Center(child: Text('${index + 1}'))),
      title: Text(row.query, style: TextStyle(color: faded, decoration: strike)),
      subtitle: !row.done
          ? const Text('Searching…')
          : found == null
              ? Text(row.problem ?? 'No match found', style: TextStyle(color: scheme.error))
              : Text('▶ ${found.title}', style: TextStyle(color: faded ?? scheme.primary, decoration: strike)),
      onTap: found == null ? null : () => _open(found.url),
      trailing: found == null
          ? null
          : TextButton(
              onPressed: () => setState(() {
                row.skipped = !row.skipped;
                _createdUrl = null;
              }),
              child: Text(row.skipped ? 'Undo' : 'Skip'),
            ),
    );
  }

  Widget _playBar(List<String> ids) {
    if (ids.length <= _chunk) {
      return FilledButton.icon(
        onPressed: () => _open(youtubePlayLink(ids)),
        icon: const Icon(Icons.play_arrow),
        label: Text('Play ${ids.length} songs on YouTube'),
      );
    }
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (var start = 0; start < ids.length; start += _chunk)
          FilledButton.icon(
            onPressed: () => _open(youtubePlayLink(ids.skip(start).take(_chunk).toList())),
            icon: const Icon(Icons.play_arrow),
            label: Text('${start + 1}–${(start + _chunk).clamp(0, ids.length)}'),
          ),
      ],
    );
  }

  Widget _createBar(List<String> ids) {
    if (_createdUrl != null) {
      return FilledButton.icon(
        onPressed: () => _open(_createdUrl!),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Playlist created — open in Spotify'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _playlistName,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Playlist name', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _creating ? null : _createPlaylist,
          child: Text(_creating ? 'Creating…' : 'Create (${ids.length})'),
        ),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.number, this.title);
  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          child: Text('$number', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      ],
    );
  }
}
