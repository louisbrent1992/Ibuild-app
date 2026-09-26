import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours borrowed from transit signage: a cobalt line, amber for a train
/// in motion, green for arrived and red for stopped.
abstract final class Palette {
  static const porcelain = Color(0xFFF2F4F6);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14213D);
  static const inkSoft = Color(0xFF59647A);
  static const rail = Color(0xFFD3D9E1);
  static const cobalt = Color(0xFF2F5BEA);
  static const cobaltLight = Color(0xFF7D9BFF);
  static const amber = Color(0xFFE39B00);
  static const go = Color(0xFF1E8C5A);
  static const stop = Color(0xFFC8372D);

  static const night = Color(0xFF0E1628);
  static const nightSurface = Color(0xFF172139);
  static const nightRail = Color(0xFF2E3A58);
  static const mist = Color(0xFFE4E9F2);
  static const mistSoft = Color(0xFF9AA5BA);

  static const terminal = Color(0xFF101A30);
  static const terminalText = Color(0xFFD8E0EE);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? Palette.cobaltLight : Palette.cobalt,
    onPrimary: dark ? Palette.night : Colors.white,
    secondary: Palette.amber,
    onSecondary: Palette.ink,
    error: Palette.stop,
    onError: Colors.white,
    surface: dark ? Palette.nightSurface : Palette.paper,
    onSurface: dark ? Palette.mist : Palette.ink,
    onSurfaceVariant: dark ? Palette.mistSoft : Palette.inkSoft,
    outline: dark ? Palette.nightRail : Palette.rail,
    outlineVariant: dark ? Palette.nightRail : Palette.rail,
  );
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? Palette.night : Palette.porcelain,
    textTheme: GoogleFonts.overpassTextTheme(base.textTheme)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
  );
}

/// Monospaced text for logs and generated configuration.
TextStyle monoStyle({double size = 12, Color? color}) =>
    GoogleFonts.overpassMono(fontSize: size, height: 1.55, color: color);

InputDecoration fieldDecoration(
  BuildContext context,
  String label, {
  String? hint,
  String? helper,
}) {
  final scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    filled: true,
    fillColor: scheme.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.primary, width: 2),
    ),
  );
}
