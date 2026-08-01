import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/theme/app_theme.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/track_card.dart';

/// Every Dart source file under `lib/`, used by the source-level contracts
/// below. Those contracts exist because the duplication they guard against was
/// re-introduced by copy-paste several times before the shared widgets landed.
List<File> _libSources() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

String _basename(File file) => file.uri.pathSegments.last;

Widget _hostSliver(Widget sliver) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: CustomScrollView(slivers: [sliver])),
  );
}

void main() {
  group('AppTokens', () {
    test('is registered on both themes', () {
      expect(AppTheme.light().extension<AppTokens>(), AppTokens.standard);
      expect(AppTheme.dark().extension<AppTokens>(), AppTokens.standard);
      expect(
        AppTheme.dark(isAmoled: true).extension<AppTokens>(),
        AppTokens.standard,
      );
    });

    testWidgets('context.tokens falls back to the standard scale', (
      tester,
    ) async {
      AppTokens? seen;
      await tester.pumpWidget(
        MaterialApp(
          // A bare ThemeData registers no extension; widgets must still work.
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              seen = context.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, AppTokens.standard);
    });

    test('lerp interpolates the scale instead of snapping', () {
      const other = AppTokens.standard;
      final doubled = other.copyWith(radiusCard: 40);
      final mid = other.lerp(doubled, 0.5);

      expect(mid.radiusCard, (other.radiusCard + 40) / 2);
    });

    test('badge text stays legible', () {
      // 9-10px badge labels were the accessibility floor violation this token
      // was introduced to fix.
      expect(AppTokens.standard.badgeFontSize, greaterThanOrEqualTo(11));
    });

    test('minimum touch target matches the Material floor', () {
      expect(AppTokens.standard.minTouchTarget, 48);
    });
  });

  group('AppSearchField', () {
    testWidgets('uses the shared filled search style and clears input', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'quality');
      var cleared = false;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppSearchField(
              controller: controller,
              hintText: 'Search settings',
              clearTooltip: 'Clear',
              onChanged: (_) {},
              onClear: () => cleared = true,
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      final border = field.decoration!.enabledBorder! as OutlineInputBorder;

      expect(field.decoration!.filled, isTrue);
      expect(border.borderRadius.topLeft.x, AppTokens.standard.radiusSheet);
      expect(find.byIcon(Icons.clear), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
    });
  });

  group('Now Playing actions', () {
    test('uses the app bottom sheet instead of a platform popup menu', () {
      final source = File(
        'lib/screens/now_playing_screen.dart',
      ).readAsStringSync();

      expect(source, contains('showAppBottomSheet<String>'));
      expect(source, isNot(contains('PopupMenuButton')));
    });
  });

  group('CoverPalette', () {
    test('local cache identity changes when artwork is replaced in place', () {
      final directory = Directory.systemTemp.createTempSync(
        'spotiflac-cover-palette-',
      );
      final file = File('${directory.path}/cover.jpg');
      try {
        file.writeAsBytesSync(const [1, 2, 3]);
        file.setLastModifiedSync(DateTime.utc(2026, 1, 1));
        final before = CoverPalette.cacheKeyFor(file.path, Brightness.dark);

        file.writeAsBytesSync(const [4, 5, 6, 7]);
        file.setLastModifiedSync(DateTime.utc(2026, 1, 2));
        final after = CoverPalette.cacheKeyFor(file.path, Brightness.dark);

        expect(after, isNot(before));
      } finally {
        directory.deleteSync(recursive: true);
      }
    });
  });

  group('AppSliverHeader', () {
    testWidgets('tab root variant shows the title without a back button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _hostSliver(const AppSliverHeader.tabRoot(title: 'Library')),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('page variant shows a back button that pops the route', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: CustomScrollView(
                        slivers: [AppSliverHeader.page(title: 'Downloads')],
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsNothing);
    });

    testWidgets('expanded title uses the shared type ramp', (tester) async {
      await tester.pumpWidget(
        _hostSliver(const AppSliverHeader.tabRoot(title: 'Home')),
      );

      final style = tester.widget<Text>(find.text('Home')).style!;
      expect(style.fontSize, AppTokens.standard.headerExpandedTitleSize);
    });

    test('is the only collapsing header implementation left', () {
      final offenders = _libSources()
          .where(
            (file) =>
                file.readAsStringSync().contains('expandedTitleScale') &&
                _basename(file) != 'app_sliver_header.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Collapsing headers must go through AppSliverHeader so the type '
            'ramp cannot fork again.',
      );
    });
  });

  group('AppBottomSheet', () {
    testWidgets('supplies one handle plus the title block', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  title: 'Open on',
                  subtitle: 'Track - Artist',
                  builder: (_) => const Text('body'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AppSheetHandle), findsOneWidget);
      expect(find.text('Open on'), findsOneWidget);
      expect(find.text('Track - Artist'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('draggable content moves as one surface and dismisses', (
      tester,
    ) async {
      const sheetKey = ValueKey<String>('scrollable-sheet');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  // Disable the route recognizer so the draggable surface,
                  // rather than the modal's fallback gesture, is under test.
                  enableDrag: false,
                  builder: (_) => AppDraggableSheet(
                    builder: (_, scrollController) => Material(
                      key: sheetKey,
                      child: ListView(
                        controller: scrollController,
                        children: const [
                          SizedBox(height: 800, child: Text('sheet body')),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(sheetKey), findsOneWidget);

      final initialTop = tester.getTopLeft(find.byKey(sheetKey)).dy;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(sheetKey)),
      );
      await gesture.moveBy(const Offset(0, 160));
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(sheetKey)).dy,
        greaterThan(initialTop + 100),
      );

      await gesture.moveBy(const Offset(0, 260));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(sheetKey), findsNothing);
    });

    testWidgets('sheet shape comes from the token scale', (tester) async {
      final shape =
          AppTheme.light().bottomSheetTheme.shape! as RoundedRectangleBorder;
      final radius = shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;

      expect(radius, AppTokens.standard.radiusSheet);
    });

    test('no screen hand-rolls a drag handle any more', () {
      final handlePattern = RegExp(
        r'height:\s*4,[\s\S]{0,200}?BorderRadius\.circular\(2\)',
      );
      final offenders = _libSources()
          .where(
            (file) =>
                handlePattern.hasMatch(file.readAsStringSync()) &&
                _basename(file) != 'app_bottom_sheet.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason: 'Use AppSheetHandle instead of rebuilding the pill.',
      );
    });

    test('no call site overrides the modal sheet shape', () {
      final shapeOverride = RegExp(
        r'shape:\s*(?:const\s+)?RoundedRectangleBorder\(\s*borderRadius:\s*'
        r'(?:const\s+)?BorderRadius\.vertical\(',
      );
      final offenders = _libSources()
          .where(
            (file) =>
                shapeOverride.hasMatch(file.readAsStringSync()) &&
                _basename(file) != 'app_theme.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Sheet radius belongs to bottomSheetTheme, which reads '
            'AppTokens.radiusSheet.',
      );
    });
  });

  group('TrackCard', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    testWidgets('lays out leading, title, subtitle and trailing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const TrackCard(
            leading: Icon(Icons.music_note),
            title: 'Song',
            subtitle: Text('Artist'),
            trailing: Icon(Icons.play_arrow),
          ),
        ),
      );

      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('selection mode swaps the trailing action for a tick', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const TrackCard(
            leading: Icon(Icons.music_note),
            title: 'Song',
            trailing: Icon(Icons.play_arrow),
            isSelectionMode: true,
            isSelected: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('flat style keeps the row transparent', (tester) async {
      await tester.pumpWidget(
        host(
          const TrackCard(
            leading: SizedBox.shrink(),
            title: 'Song',
            style: TrackCardStyle.flat,
          ),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, Colors.transparent);
    });

    testWidgets('flat style keeps trailing actions near the card edge', (
      tester,
    ) async {
      const trailingKey = Key('flat-trailing');
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: TrackCard(
              leading: SizedBox(width: 24),
              title: 'Song',
              style: TrackCardStyle.flat,
              trailing: SizedBox(key: trailingKey, width: 48, height: 48),
            ),
          ),
        ),
      );

      final cardRect = tester.getRect(find.byType(Card));
      final trailingRect = tester.getRect(find.byKey(trailingKey));
      // Card's render box includes its 8dp flat-row margin; content itself is
      // inset another 6dp from the painted card edge.
      expect(cardRect.right - trailingRect.right, 14);
    });

    testWidgets('grid variant is a real button with a semantic label', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            child: TrackGridCard(
              cover: const ColoredBox(color: Colors.grey),
              title: 'Song',
              subtitle: const Text('Artist'),
              semanticLabel: 'Song by Artist',
              onTap: () => taps++,
            ),
          ),
        ),
      );

      // A bare GestureDetector gave no ripple and no semantics; the shared
      // card uses InkWell + Semantics instead.
      expect(find.byType(InkWell), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });

  group('selection bar', () {
    test('root-overlay mounting lives in exactly one place', () {
      final offenders = _libSources()
          .where(
            (file) =>
                file.readAsStringSync().contains('OverlayEntry(') &&
                _basename(file) != 'selection_bottom_bar.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Selection bars must mount through SelectionOverlayController so '
            'they animate identically and clear the shell navigation bar.',
      );
    });

    testWidgets('shell host keeps modal routes above the selection bar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SelectionOverlayController();
      addTearDown(controller.dispose);
      BuildContext? pageContext;
      var selectionTaps = 0;
      var sheetTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SelectionOverlayHost(
            child: Builder(
              builder: (context) {
                pageContext = context;
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        ),
      );

      controller.show(
        pageContext!,
        (_) => GestureDetector(
          key: const ValueKey('selection-hit-target'),
          behavior: HitTestBehavior.opaque,
          onTap: () => selectionTaps++,
          child: const SizedBox(height: 200),
        ),
      );
      await tester.pumpAndSettle();

      final sheetClosed = showModalBottomSheet<void>(
        context: pageContext!,
        useRootNavigator: true,
        enableDrag: false,
        builder: (_) => GestureDetector(
          key: const ValueKey('sheet-hit-target'),
          behavior: HitTestBehavior.opaque,
          onTap: () => sheetTaps++,
          child: const SizedBox(height: 300),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sheet-hit-target')), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-hit-target')), findsNothing);
      expect(selectionTaps, 0);
      expect(sheetTaps, 0);

      Navigator.of(pageContext!, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await sheetClosed;

      expect(
        find.byKey(const ValueKey('selection-hit-target')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('selection-hit-target')));
      await tester.pump();
      expect(selectionTaps, 1);
    });
  });

  group('CollectionScaffold', () {
    testWidgets('mounts the selection bar only while selecting', (
      tester,
    ) async {
      Widget host({required bool selecting}) => MaterialApp(
        theme: AppTheme.light(),
        home: CollectionScaffold(
          scrollController: ScrollController(),
          isSelectionMode: selecting,
          onExitSelectionMode: () {},
          bottomInset: 0,
          appBar: const SliverToBoxAdapter(child: SizedBox(height: 10)),
          slivers: const [SliverToBoxAdapter(child: Text('content'))],
          selectionBar: const Text('selection-bar'),
        ),
      );

      await tester.pumpWidget(host(selecting: false));
      await tester.pumpAndSettle();
      expect(find.text('selection-bar'), findsNothing);

      await tester.pumpWidget(host(selecting: true));
      await tester.pumpAndSettle();
      expect(find.text('selection-bar'), findsOneWidget);

      await tester.pumpWidget(host(selecting: false));
      await tester.pumpAndSettle();
      expect(find.text('selection-bar'), findsNothing);
    });

    testWidgets('reserves the measured height of a multi-row selection bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CollectionScaffold(
            scrollController: ScrollController(),
            isSelectionMode: true,
            onExitSelectionMode: () {},
            bottomInset: 0,
            appBar: const SliverToBoxAdapter(child: SizedBox(height: 10)),
            slivers: const [SliverToBoxAdapter(child: Text('content'))],
            selectionBar: const SizedBox(height: 260),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(find.byKey(const ValueKey('collection-selection-spacer')))
            .height,
        260,
      );
    });

    test('every collection screen goes through the shared shell', () {
      const screens = [
        'album_screen.dart',
        'playlist_screen.dart',
        'local_album_screen.dart',
        'downloaded_album_screen.dart',
        'library_tracks_folder_screen.dart',
      ];
      final offenders = <String>[];
      for (final name in screens) {
        final file = _libSources().firstWhere(
          (candidate) => _basename(candidate) == name,
        );
        if (!file.readAsStringSync().contains('CollectionScaffold(')) {
          offenders.add(name);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Collection screens must share CollectionScaffold; hand-rolled '
            'Scaffold + PopScope + selection plumbing is what let the four '
            'album-style screens drift apart.',
      );
    });

    test('the playlist screen supports multi-select', () {
      final playlist = _libSources().firstWhere(
        (file) => _basename(file) == 'playlist_screen.dart',
      );
      final source = playlist.readAsStringSync();

      expect(source, contains('SelectionModeMixin<PlaylistScreen>'));
      expect(source, contains('SelectionBottomBar('));
      expect(source, contains('isSelectionMode: isSelectionMode'));
    });
  });

  group('settings components', () {
    testWidgets('choice chip meets the minimum touch target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                SettingsChoiceChip(
                  label: 'Stable',
                  isSelected: true,
                  onTap: () {},
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(SettingsChoiceChip));
      expect(
        size.height,
        greaterThanOrEqualTo(AppTokens.standard.minTouchTarget),
      );
    });

    testWidgets('info card renders title, message and action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SettingsInfoCard(
              icon: Icons.warning_amber_outlined,
              tone: SettingsInfoTone.error,
              title: 'Folder lost',
              message: 'Pick it again',
              action: TextButton(onPressed: () {}, child: const Text('Fix')),
            ),
          ),
        ),
      );

      expect(find.text('Folder lost'), findsOneWidget);
      expect(find.text('Pick it again'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
    });
  });
}
