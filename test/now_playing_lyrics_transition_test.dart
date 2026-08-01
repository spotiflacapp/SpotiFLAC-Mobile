import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/screens/now_playing_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backendChannel = MethodChannel('com.zarz.spotiflac/backend');
  late StreamController<MediaItem?> mediaItems;

  setUp(() {
    mediaItems = StreamController<MediaItem?>.broadcast();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (call.method != 'readFileMetadata') {
            fail('Unexpected platform call: ${call.method}');
          }
          final arguments = (call.arguments as Map).cast<String, dynamic>();
          final path = arguments['file_path']?.toString() ?? '';
          return jsonEncode({
            'title': path.endsWith('/second.flac') ? 'Second' : 'First',
            'lyrics': path.endsWith('/second.flac')
                ? '[00:01.00]Second lyric'
                : '[00:01.00]First lyric',
          });
        });
  });

  tearDown(() async {
    await mediaItems.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
  });

  MediaItem item(String id) => MediaItem(
    id: id,
    title: id == 'first' ? 'First' : 'Second',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(minutes: 3),
    extras: {'source': 'content://library/$id.flac'},
  );

  Future<void> pumpNowPlaying(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWith((ref) => mediaItems.stream),
          playbackStateProvider.overrideWith((ref) => const Stream.empty()),
          playQueueProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NowPlayingScreen(),
        ),
      ),
    );
  }

  testWidgets(
    'automatic SAF track change refreshes lyrics while Lyrics page is active',
    (tester) async {
      await pumpNowPlaying(tester);

      mediaItems.add(item('first'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text('First lyric'), findsOneWidget);

      mediaItems.add(item('second'));
      await tester.pumpAndSettle();

      expect(find.text('Second lyric'), findsOneWidget);
      expect(find.text('First lyric'), findsNothing);
    },
  );

  testWidgets('Now Playing menu exposes Go to Album when album is known', (
    tester,
  ) async {
    await pumpNowPlaying(tester);
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Go to Album'), findsOneWidget);
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
  });
}
