import 'package:flutter/material.dart';

import 'app_themes.dart';

/// Builds a flat, compact theme in the spirit of shadcn/ui: neutral surfaces,
/// 1px borders, 6–10px radii, no ripples, no heavy elevation. Material is only
/// the widget toolkit underneath; nothing here should look "Material".
ThemeData buildThemeData(AppThemeSpec s) {
  final dark = s.brightness == Brightness.dark;
  final onPrimary = s.primary.computeLuminance() > 0.55 ? const Color(0xFF111111) : Colors.white;
  final hover = s.text.withValues(alpha: dark ? 0.07 : 0.05);
  final pressed = s.text.withValues(alpha: dark ? 0.11 : 0.08);
  final focusRing = s.primary.withValues(alpha: 0.55);

  final scheme = ColorScheme.fromSeed(seedColor: s.primary, brightness: s.brightness).copyWith(
    primary: s.primary,
    onPrimary: onPrimary,
    secondary: s.primary,
    onSecondary: onPrimary,
    surface: s.surface,
    onSurface: s.text,
    onSurfaceVariant: s.muted,
    surfaceContainerLowest: s.background,
    surfaceContainerLow: s.background,
    surfaceContainer: s.surface,
    surfaceContainerHigh: s.surfaceAlt,
    surfaceContainerHighest: s.surfaceAlt,
    outline: s.border,
    outlineVariant: s.border,
    secondaryContainer: s.surfaceAlt,
    onSecondaryContainer: s.text,
    error: const Color(0xFFE5534B),
    inverseSurface: dark ? const Color(0xFFEDECE8) : const Color(0xFF2B2A27),
    onInverseSurface: dark ? const Color(0xFF1F1E1D) : const Color(0xFFF5F4EE),
  );

  final base = ThemeData(
    colorScheme: scheme,
    brightness: s.brightness,
    useMaterial3: true,
    fontFamily: uiFamily,
    fontFamilyFallback: uiFallback,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
  );

  // Smaller, desktop-like type scale.
  final t = base.textTheme;
  final colored = t.apply(bodyColor: s.text, displayColor: s.text);
  final text = colored.copyWith(
    headlineSmall: colored.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2),
    titleLarge: colored.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
    titleMedium: colored.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    titleSmall: colored.titleSmall?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
    bodyLarge: colored.bodyLarge?.copyWith(fontSize: 14, height: 1.45),
    bodyMedium: colored.bodyMedium?.copyWith(fontSize: 13.5, height: 1.45),
    bodySmall: colored.bodySmall?.copyWith(fontSize: 12, color: s.muted),
    labelLarge: colored.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
    labelMedium: colored.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
  );

  RoundedRectangleBorder rr(double r, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);
  final border = BorderSide(color: s.border);
  final buttonText = WidgetStatePropertyAll(text.labelLarge);
  const buttonPadding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 0));
  const buttonSize = WidgetStatePropertyAll(Size(0, 32));
  WidgetStateProperty<Color?> overlay(Color h, Color p) => WidgetStateProperty.resolveWith(
    (st) => st.contains(WidgetState.pressed) ? p : (st.contains(WidgetState.hovered) ? h : null),
  );

  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(7),
    borderSide: BorderSide(color: c, width: w),
  );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: s.background,
    canvasColor: s.surface,
    dividerColor: s.border,
    hoverColor: hover,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    focusColor: hover,
    dividerTheme: DividerThemeData(color: s.border, space: 1, thickness: 1),
    iconTheme: IconThemeData(color: s.muted, size: 18),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 44,
      shape: Border(bottom: border),
      titleTextStyle: text.titleSmall,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.disabled) ? s.primary.withValues(alpha: 0.35) : s.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.disabled) ? onPrimary.withValues(alpha: 0.7) : onPrimary,
        ),
        overlayColor: overlay(Colors.white.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.10)),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(rr(7)),
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonSize,
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(s.text),
        backgroundColor: WidgetStatePropertyAll(s.surface),
        overlayColor: overlay(hover, pressed),
        side: WidgetStatePropertyAll(border),
        shape: WidgetStatePropertyAll(rr(7)),
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonSize,
        iconSize: const WidgetStatePropertyAll(16),
        iconColor: WidgetStatePropertyAll(s.muted),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.disabled) ? s.muted.withValues(alpha: 0.5) : s.text,
        ),
        overlayColor: overlay(hover, pressed),
        shape: WidgetStatePropertyAll(rr(7)),
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonSize,
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.text : s.muted),
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? hover : null),
        overlayColor: overlay(hover, pressed),
        shape: WidgetStatePropertyAll(rr(7)),
        iconSize: const WidgetStatePropertyAll(18),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.surfaceAlt : s.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.text : s.muted),
        overlayColor: overlay(hover, pressed),
        side: WidgetStatePropertyAll(border),
        shape: WidgetStatePropertyAll(rr(7)),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
        iconSize: const WidgetStatePropertyAll(15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark ? Colors.black.withValues(alpha: 0.12) : Colors.white,
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      hintStyle: TextStyle(color: s.muted.withValues(alpha: 0.8), fontSize: 13.5),
      labelStyle: TextStyle(color: s.muted, fontSize: 13.5),
      floatingLabelStyle: TextStyle(color: s.muted, fontSize: 13),
      border: inputBorder(s.border),
      enabledBorder: inputBorder(s.border),
      focusedBorder: inputBorder(focusRing, 1.5),
      errorBorder: inputBorder(scheme.error),
      focusedErrorBorder: inputBorder(scheme.error, 1.5),
      prefixIconColor: s.muted,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: s.primary,
      selectionColor: s.primary.withValues(alpha: 0.3),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? onPrimary : Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (st) =>
            st.contains(WidgetState.selected) ? s.primary : (dark ? const Color(0xFF4A4945) : const Color(0xFFD8D5CB)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: s.primary,
      inactiveTrackColor: s.surfaceAlt,
      thumbColor: s.primary,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0, pressedElevation: 0),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      showValueIndicator: ShowValueIndicator.never,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: rr(4),
      side: BorderSide(color: s.muted),
      fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.primary : null),
      checkColor: WidgetStatePropertyAll(onPrimary),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: s.surface,
      selectedColor: s.surfaceAlt,
      side: border,
      shape: rr(7),
      showCheckmark: false,
      labelStyle: text.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    cardTheme: CardThemeData(color: s.surface, elevation: 0, margin: EdgeInsets.zero, shape: rr(10, border)),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: rr(12, border),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium,
      barrierColor: Colors.black.withValues(alpha: dark ? 0.55 : 0.3),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: rr(9, border),
      textStyle: text.bodyMedium,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(s.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.35)),
        shape: WidgetStatePropertyAll(rr(9, border)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        overlayColor: overlay(hover, pressed),
        shape: WidgetStatePropertyAll(rr(6)),
        textStyle: WidgetStatePropertyAll(text.bodyMedium),
        minimumSize: const WidgetStatePropertyAll(Size(180, 34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      textStyle: TextStyle(fontSize: 12, color: scheme.onInverseSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(6)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
      actionTextColor: s.primary,
      elevation: 4,
      shape: rr(9),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: s.text,
      unselectedLabelColor: s.muted,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: text.labelLarge,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(borderSide: BorderSide(color: s.text, width: 2)),
      dividerColor: s.border,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(s.muted.withValues(alpha: 0.35)),
    ),
    badgeTheme: BadgeThemeData(backgroundColor: s.primary, textColor: onPrimary),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),
    listTileTheme: ListTileThemeData(
      dense: true,
      shape: rr(7),
      iconColor: s.muted,
      titleTextStyle: text.bodyMedium,
      subtitleTextStyle: text.bodySmall,
    ),
    extensions: [s.diff],
  );
}
