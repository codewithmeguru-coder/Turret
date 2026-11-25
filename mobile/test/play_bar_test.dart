import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotify_youtube/play_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(List<String> ids, YoutubeResult mode, List<String> opened, {int chunk = 50}) => MaterialApp(
        home: Scaffold(
          body: PlayBar(ids: ids, mode: mode, chunk: chunk, onOpen: opened.add, onModeChanged: (_) {}),
        ),
      );

  testWidgets('open mode opens the play link', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(host(['a', 'b'], YoutubeResult.open, opened));
    await tester.tap(find.text('Play 2 songs on YouTube'));
    expect(opened, ['https://www.youtube.com/watch_videos?video_ids=a,b']);
  });

  testWidgets('show-link mode shows and copies the link without opening it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final opened = <String>[];
    await tester.pumpWidget(host(['a', 'b'], YoutubeResult.showLink, opened));

    const url = 'https://www.youtube.com/watch_videos?video_ids=a,b';
    expect(find.widgetWithText(SelectableText, url), findsOneWidget);
    expect(find.textContaining('Play'), findsNothing);

    await tester.tap(find.byTooltip('Copy link'));
    await tester.pump();
    expect(copied, url);
    expect(opened, isEmpty);
    expect(find.textContaining('Link copied'), findsOneWidget);
  });

  testWidgets('show-link mode lists one link per batch', (tester) async {
    await tester.pumpWidget(host(['a', 'b', 'c'], YoutubeResult.showLink, [], chunk: 2));
    expect(find.text('Songs 1–2'), findsOneWidget);
    expect(find.text('Songs 3–3'), findsOneWidget);
    expect(find.byTooltip('Copy link'), findsNWidgets(2));
  });

  test('the choice is saved, and opening is the default', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadYoutubeResult(), YoutubeResult.open);
    await saveYoutubeResult(YoutubeResult.showLink);
    expect(await loadYoutubeResult(), YoutubeResult.showLink);
  });
}
