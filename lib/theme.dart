import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hevyfin: streaming-service black with Hevyfin orange.
abstract final class Hy {
  static const bg = Color(0xFF0E0E0E);
  static const surface = Color(0xFF181818);
  static const surfaceHigh = Color(0xFF232323);
  static const hover = Color(0xFF262626);
  static const active = Color(0xFF2F2F2F);
  static const border = Color(0xFF2A2A2A);

  static const orange = Color(0xFFFF7A1A);
  static const orangeBright = Color(0xFFFF9A45);
  static const orangeDeep = Color(0xFFE85A00);

  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xFFB3B3B3);
  static const textMute = Color(0xFF7C7C7C);
  static const danger = Color(0xFFFF5470);

  static const radius = 6.0;
  static const orangeGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [orangeBright, orangeDeep]);

  /// Stable, pleasant gradient for a string (genre tiles, placeholders), kept warm.
  static LinearGradient gradientFor(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    final hue2 = (hue + 40 + h % 50) % 360;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [HSLColor.fromAHSL(1, hue, .65, .5).toColor(), HSLColor.fromAHSL(1, hue2, .7, .34).toColor()],
    );
  }

  /// An orange outline on whatever the remote or keyboard is on.
  static final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
    (s) => s.contains(WidgetState.focused) ? const BorderSide(color: orange, width: 3) : null,
  );

  /// TV: the button under the remote turns white with black text, like the menu, the
  /// season pills and the posters' white frame, so it reads from across the room.
  static ButtonStyle _tvFocus(ButtonStyle s) => s.copyWith(
    backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused) ? Colors.white : s.backgroundColor?.resolve(st)),
    foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused) ? Colors.black : s.foregroundColor?.resolve(st)),
    iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused) ? Colors.black : s.iconColor?.resolve(st)),
    side: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused) ? const BorderSide(color: orange, width: 3) : s.side?.resolve(st)),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static ThemeData theme({bool tv = false}) {
    final t = theme0();
    if (!tv) return t;
    return t.copyWith(
      filledButtonTheme: FilledButtonThemeData(style: _tvFocus(t.filledButtonTheme.style!)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _tvFocus(t.outlinedButtonTheme.style!)),
      textButtonTheme: TextButtonThemeData(style: _tvFocus(t.textButtonTheme.style!)),
      iconButtonTheme: IconButtonThemeData(style: _tvFocus(t.iconButtonTheme.style!)),
    );
  }

  static ThemeData theme0() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: orange, onPrimary: Colors.black, secondary: orangeBright, surface: surface, onSurface: text, error: danger),
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.white.withValues(alpha: .06),
      focusColor: orange.withValues(alpha: .28),
      dividerColor: border,
    );
    final textTheme = GoogleFonts.interTightTextTheme(base.textTheme).apply(bodyColor: Hy.text, displayColor: Hy.text);
    return base.copyWith(
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: textDim, size: 22),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: Hy.orange,
        inactiveTrackColor: Colors.white.withValues(alpha: .18),
        thumbColor: Hy.orange,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: const TextStyle(color: textMute),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: orange, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: orange,
          foregroundColor: Colors.black,
          textStyle: GoogleFonts.interTight(fontWeight: FontWeight.w700, fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ).copyWith(side: focusSide),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: Hy.text,
              side: const BorderSide(color: textMute),
              textStyle: GoogleFonts.interTight(fontWeight: FontWeight.w700, fontSize: 14),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.focused) ? const BorderSide(color: orange, width: 3) : const BorderSide(color: textMute),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Hy.text).copyWith(side: focusSide),
      ),
      iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: focusSide)),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: orange,
        labelStyle: GoogleFonts.interTight(fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: GoogleFonts.interTight(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: GoogleFonts.interTight(color: Hy.text, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: GoogleFonts.interTight(color: Hy.text, fontSize: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: surfaceHigh, borderRadius: BorderRadius.circular(4)),
        textStyle: GoogleFonts.interTight(color: Hy.text, fontSize: 12, fontWeight: FontWeight.w600),
        waitDuration: const Duration(milliseconds: 500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white.withValues(alpha: .22)),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder(), TargetPlatform.linux: FadeForwardsPageTransitionsBuilder()},
      ),
    );
  }
}

extension HyText on BuildContext {
  TextTheme get text => Theme.of(this).textTheme;
  bool get isWide => MediaQuery.sizeOf(this).width >= 840;
}
