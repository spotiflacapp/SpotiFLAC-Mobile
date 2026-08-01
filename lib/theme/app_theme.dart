import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';

class AppTheme {
  static const Color defaultSeedColor = Color(kDefaultSeedColor);

  /// Component radii resolve from the same tokens the widgets read, so the
  /// scale cannot drift between `ThemeData` and hand-built containers.
  static const AppTokens _tokens = AppTokens.standard;

  // Override Flutter's default page transitions. Recent Flutter defaults the
  // Android route transition to PredictiveBackPageTransitionsBuilder, whose
  // gesture detector mis-routes the predictive-back gesture to a nested
  // Navigator instead of the topmost route (flutter#152323). That pops the page
  // *behind* a root modal/sheet/dialog instead of closing the modal first — a
  // regression introduced by the Flutter upgrade. Forcing a non-predictive
  // builder restores the correct back order (close modal, then pop page), at the
  // cost of the predictive-back preview animation.
  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      );

  static ThemeData light({ColorScheme? dynamicScheme, Color? seedColor}) {
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor ?? defaultSeedColor,
          brightness: Brightness.light,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      pageTransitionsTheme: _pageTransitionsTheme,
      appBarTheme: _appBarTheme(scheme),
      cardTheme: _cardTheme(scheme),
      elevatedButtonTheme: _elevatedButtonTheme(scheme),
      filledButtonTheme: _filledButtonTheme(scheme),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: _textButtonTheme(scheme),
      floatingActionButtonTheme: _fabTheme(scheme),
      inputDecorationTheme: _inputDecorationTheme(scheme),
      listTileTheme: _listTileTheme(scheme),
      dialogTheme: _dialogTheme(scheme),
      bottomSheetTheme: _bottomSheetTheme,
      navigationBarTheme: _navigationBarTheme(scheme),
      snackBarTheme: _snackBarTheme(scheme),
      progressIndicatorTheme: _progressIndicatorTheme(scheme),
      switchTheme: _switchTheme(scheme),
      chipTheme: _chipTheme(scheme),
      dividerTheme: _dividerTheme(scheme),
      extensions: const <ThemeExtension<dynamic>>[AppTokens.standard],
      fontFamily: 'Google Sans Flex',
    );
  }

  static ThemeData dark({
    ColorScheme? dynamicScheme,
    Color? seedColor,
    bool isAmoled = false,
  }) {
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor ?? defaultSeedColor,
          brightness: Brightness.dark,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      pageTransitionsTheme: _pageTransitionsTheme,
      scaffoldBackgroundColor: isAmoled ? Colors.black : null,
      appBarTheme: _appBarTheme(scheme, isAmoled: isAmoled),
      cardTheme: _cardTheme(scheme),
      elevatedButtonTheme: _elevatedButtonTheme(scheme),
      filledButtonTheme: _filledButtonTheme(scheme),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: _textButtonTheme(scheme),
      floatingActionButtonTheme: _fabTheme(scheme),
      inputDecorationTheme: _inputDecorationTheme(scheme),
      listTileTheme: _listTileTheme(scheme),
      dialogTheme: _dialogTheme(scheme),
      bottomSheetTheme: _bottomSheetTheme,
      navigationBarTheme: _navigationBarTheme(scheme, isAmoled: isAmoled),
      snackBarTheme: _snackBarTheme(scheme),
      progressIndicatorTheme: _progressIndicatorTheme(scheme),
      switchTheme: _switchTheme(scheme),
      chipTheme: _chipTheme(scheme),
      dividerTheme: _dividerTheme(scheme),
      extensions: const <ThemeExtension<dynamic>>[AppTokens.standard],
      fontFamily: 'Google Sans Flex',
    );
  }

  static AppBarTheme _appBarTheme(
    ColorScheme scheme, {
    bool isAmoled = false,
  }) => AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: isAmoled ? 0 : 3,
    backgroundColor: isAmoled ? Colors.black : scheme.surface,
    foregroundColor: scheme.onSurface,
    surfaceTintColor: isAmoled ? Colors.transparent : scheme.surfaceTint,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: scheme.onSurface,
      fontSize: 22,
      fontWeight: FontWeight.w500,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: scheme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarColor: isAmoled
          ? Colors.black
          : scheme.surfaceContainer,
      systemNavigationBarIconBrightness: scheme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ),
  );

  static CardThemeData _cardTheme(ColorScheme scheme) => CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_tokens.radiusControl),
    ),
    color: scheme.surfaceContainerLow,
    surfaceTintColor: scheme.surfaceTint,
  );

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_tokens.radiusControl),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(ColorScheme scheme) =>
      FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_tokens.radiusControl),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme scheme) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_tokens.radiusControl),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      );

  static TextButtonThemeData _textButtonTheme(ColorScheme scheme) =>
      TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_tokens.radiusControl),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      );

  static FloatingActionButtonThemeData _fabTheme(ColorScheme scheme) =>
      FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusControl),
        ),
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      );

  static InputDecorationTheme _inputDecorationTheme(ColorScheme scheme) =>
      InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusControl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusControl),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusControl),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusControl),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      );

  static ListTileThemeData _listTileTheme(ColorScheme scheme) =>
      ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusControl),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );

  // Caps modal sheet width on tablets/landscape (no effect on phones, whose
  // screens are narrower); Flutter centers the sheet when narrower than the
  // screen. The shape is set here so no call site has to repeat it — every
  // sheet inherits the token radius.
  static final BottomSheetThemeData _bottomSheetTheme = BottomSheetThemeData(
    constraints: const BoxConstraints(maxWidth: 640),
    shape: _tokens.sheetShape,
  );

  static DialogThemeData _dialogTheme(ColorScheme scheme) => DialogThemeData(
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_tokens.radiusSheet),
    ),
    backgroundColor: scheme.surfaceContainerHigh,
    surfaceTintColor: scheme.surfaceTint,
  );

  static NavigationBarThemeData _navigationBarTheme(
    ColorScheme scheme, {
    bool isAmoled = false,
  }) => NavigationBarThemeData(
    elevation: 0,
    backgroundColor: isAmoled ? Colors.black : scheme.surfaceContainer,
    indicatorColor: scheme.secondaryContainer,
    surfaceTintColor: isAmoled ? Colors.transparent : scheme.surfaceTint,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
  );

  static SnackBarThemeData _snackBarTheme(ColorScheme scheme) =>
      SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_tokens.radiusThumb),
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      );

  static ProgressIndicatorThemeData _progressIndicatorTheme(
    ColorScheme scheme,
  ) => ProgressIndicatorThemeData(
    color: scheme.primary,
    linearTrackColor: scheme.surfaceContainerHighest,
    circularTrackColor: scheme.surfaceContainerHighest,
  );

  static SwitchThemeData _switchTheme(ColorScheme scheme) => SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return scheme.onPrimary;
      }
      return scheme.outline;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return scheme.primary;
      }
      return scheme.surfaceContainerHighest;
    }),
    thumbIcon: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return Icon(Icons.check, color: scheme.primary);
      }
      return null;
    }),
  );

  static ChipThemeData _chipTheme(ColorScheme scheme) => ChipThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_tokens.radiusCard),
    ),
    backgroundColor: scheme.surfaceContainerLow,
    selectedColor: scheme.secondaryContainer,
  );

  static DividerThemeData _dividerTheme(ColorScheme scheme) =>
      DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1);
}
