import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube.dart';

/// What happens with the YouTube play link once the songs are matched.
enum YoutubeResult { open, showLink }

const _prefsKey = 'youtubeResult';

/// The saved choice; opening YouTube straight away is the default.
Future<YoutubeResult> loadYoutubeResult() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey) == YoutubeResult.showLink.name ? YoutubeResult.showLink : YoutubeResult.open;
}

Future<void> saveYoutubeResult(YoutubeResult result) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, result.name);
}

/// Step 3 for Spotify → YouTube: play buttons, or the links to copy.
class PlayBar extends StatelessWidget {
  const PlayBar({
    super.key,
    required this.ids,
    required this.mode,
    required this.onModeChanged,
    required this.onOpen,
    this.chunk = 50,
  });

  final List<String> ids;
  final YoutubeResult mode;
  final ValueChanged<YoutubeResult> onModeChanged;
  final ValueChanged<String> onOpen;
  final int chunk; // YouTube's link takes at most 50 videos

  List<(String label, String url)> get _links => [
        for (var start = 0; start < ids.length; start += chunk)
          (
            ids.length <= chunk ? '${ids.length} songs' : '${start + 1}–${(start + chunk).clamp(0, ids.length)}',
            youtubePlayLink(ids.skip(start).take(chunk).toList()),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final links = _links;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<YoutubeResult>(
          segments: const [
            ButtonSegment(value: YoutubeResult.open, label: Text('Open YouTube'), icon: Icon(Icons.open_in_new)),
            ButtonSegment(value: YoutubeResult.showLink, label: Text('Show link'), icon: Icon(Icons.link)),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        const SizedBox(height: 8),
        if (mode == YoutubeResult.open)
          _openButtons(links)
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height / 3),
            child: ListView(
              shrinkWrap: true,
              children: [for (final (label, url) in links) _LinkRow(label: label, url: url, showLabel: links.length > 1)],
            ),
          ),
      ],
    );
  }

  Widget _openButtons(List<(String, String)> links) {
    if (links.length == 1) {
      return FilledButton.icon(
        onPressed: () => onOpen(links.first.$2),
        icon: const Icon(Icons.play_arrow),
        label: Text('Play ${ids.length} songs on YouTube'),
      );
    }
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, url) in links)
          FilledButton.icon(onPressed: () => onOpen(url), icon: const Icon(Icons.play_arrow), label: Text(label)),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url, required this.showLabel});
  final String label;
  final String url;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: showLabel ? Text('Songs $label') : null,
      subtitle: SelectableText(url, maxLines: 2),
      trailing: IconButton.filledTonal(
        tooltip: 'Copy link',
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Link copied. Paste it into your browser.')));
          }
        },
      ),
    );
  }
}
