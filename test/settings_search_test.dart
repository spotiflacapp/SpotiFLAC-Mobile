import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/screens/settings/about_page.dart';
import 'package:spotiflac_android/screens/settings/settings_tab.dart';
import 'package:spotiflac_android/theme/app_theme.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('finds controls nested inside a settings page', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(find.byType(TextField), 'parallel downloads');
    await tester.pump();

    expect(find.text('Concurrent downloads'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(
      find.text('No settings found for "parallel downloads"'),
      findsNothing,
    );
  });

  testWidgets(
    'returning from a search result does not restore keyboard focus',
    (tester) async {
      await pumpSettings(tester);

      final searchField = find.byType(TextField);
      await tester.tap(searchField);
      await tester.enterText(searchField, 'build number');
      await tester.pump();

      final focusedField = tester.widget<TextField>(searchField);
      expect(focusedField.focusNode?.hasFocus, isTrue);
      expect(find.text('Version'), findsOneWidget);

      await tester.tap(find.text('Version'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      final restoredField = tester.widget<TextField>(find.byType(TextField));
      expect(restoredField.focusNode?.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('Version'), findsOneWidget);
    },
  );

  testWidgets('search target scrolls into view with standard selected color', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsSearchHighlightScope(
          targetLabel: 'Target setting',
          child: Scaffold(
            body: CustomScrollView(
              controller: scrollController,
              slivers: const [
                SliverToBoxAdapter(child: SizedBox(height: 1200)),
                SliverToBoxAdapter(
                  child: SettingsItem(title: 'Target setting'),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 600)),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(scrollController.offset, greaterThan(0));
    final highlightFinder = find.byKey(
      const ValueKey('settings-highlight:Target setting'),
    );
    final highlighted = tester.widget<AnimatedContainer>(highlightFinder);
    final highlightedDecoration = highlighted.decoration! as BoxDecoration;
    final colorScheme = Theme.of(tester.element(highlightFinder)).colorScheme;
    expect(
      highlightedDecoration.color,
      colorScheme.primaryContainer.withValues(alpha: 0.3),
    );
    expect(highlightedDecoration.border, isNull);
    expect(highlightedDecoration.boxShadow, isNull);

    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 400));
    final faded = tester.widget<AnimatedContainer>(highlightFinder);
    final fadedDecoration = faded.decoration! as BoxDecoration;
    expect(fadedDecoration.color, Colors.transparent);
  });
}
