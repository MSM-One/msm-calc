import 'package:flutter/material.dart';

/// Centralized Enterprise Design Tokens for MSM Yard Inventory & Operations.
/// Adheres to high-trust B2B design patterns (Linear, Stripe, Bloomberg, SAP Fiori).
abstract class EnterpriseColors {
  // ── Neutral Palette (Canvas & Surfaces) ──
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color backgroundSecondary = Color(0xFFF1F5F9); // Slate 100
  static const Color cardSurface = Colors.white;
  static const Color cardSurfaceHover = Color(0xFFF8FAFC);

  // ── Brand Dark / Authority Navy ──
  static const Color darkNavy = Color(0xFF0F172A); // Slate 900
  static const Color darkCharcoal = Color(0xFF1E293B); // Slate 800
  static const Color darkSlate = Color(0xFF334155); // Slate 700

  // ── Subtle Borders & Dividers ──
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200
  static const Color borderSubtle = Color(0xFFEEF2F6);
  static const Color borderHover = Color(0xFFCBD5E1); // Slate 300
  static const Color borderDark = Color(0xFF334155);

  // ── Typography & Text Hierarchy ──
  static const Color textPrimary = Color(0xFF0F172A); // High contrast dark slate
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF64748B); // Slate 500
  static const Color textSubtle = Color(0xFF94A3B8); // Slate 400
  static const Color textOnDark = Colors.white;
  static const Color textOnDarkMuted = Color(0xFF94A3B8);

  // ── Functional Accents (Used Sparingly for Precision) ──
  // Steel Blue / Cyan (Hero stock, primary KPI, neutral live state)
  static const Color accentSteel = Color(0xFF0284C7); // Sky 600
  static const Color accentSteelLight = Color(0xFFE0F2FE); // Sky 100
  static const Color accentSteelBorder = Color(0xFFBAE6FD); // Sky 200

  // Emerald (Inward movement, positive deltas, live sync pulse)
  static const Color accentEmerald = Color(0xFF059669); // Emerald 600
  static const Color accentEmeraldLight = Color(0xFFECFDF5); // Emerald 50
  static const Color accentEmeraldBorder = Color(0xFFA7F3D0); // Emerald 200

  // Slate / Outward (Dispatches, sales, neutral delta)
  static const Color accentSlate = Color(0xFF475569); // Slate 600
  static const Color accentSlateLight = Color(0xFFF1F5F9); // Slate 100
  static const Color accentSlateBorder = Color(0xFFCBD5E1); // Slate 300

  // Amber / Gold (Warning, low stock threshold)
  static const Color accentAmber = Color(0xFFD97706); // Amber 600
  static const Color accentAmberLight = Color(0xFFFFFBEB); // Amber 50
  static const Color accentAmberBorder = Color(0xFFFDE68A); // Amber 200

  // Critical Rose / Ruby (Deficits, out of stock, urgent alerts)
  static const Color accentRose = Color(0xFFE11D48); // Rose 600
  static const Color accentRoseLight = Color(0xFFFFF1F2); // Rose 50
  static const Color accentRoseBorder = Color(0xFFFECDD3); // Rose 200
  static const Color accentRoseDark = Color(0xFF9F1239); // Rose 800
}

abstract class EnterpriseTypography {
  // Hero KPI figures (Tabular, monospaced digits for razor-sharp alignment)
  static const TextStyle heroNumber = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: EnterpriseColors.textPrimary,
    letterSpacing: -0.8,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle heroNumberLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: EnterpriseColors.textPrimary,
    letterSpacing: -1.0,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Card Header / Data Label (Uppercase, tracked, lower-opacity)
  static const TextStyle dataLabel = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    color: EnterpriseColors.textMuted,
    letterSpacing: 0.9,
  );

  static const TextStyle dataLabelOnDark = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    color: EnterpriseColors.textOnDarkMuted,
    letterSpacing: 0.9,
  );

  // Section Headers
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: EnterpriseColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: EnterpriseColors.textMuted,
    letterSpacing: -0.1,
  );

  // Subtitles and captions
  static const TextStyle caption = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: EnterpriseColors.textMuted,
    letterSpacing: -0.1,
  );

  // System status / Telemetry badges
  static const TextStyle badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  // Table Row Value
  static const TextStyle tableValue = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: EnterpriseColors.textPrimary,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract class EnterpriseBorders {
  static final BorderRadius r8 = BorderRadius.circular(8);
  static final BorderRadius r10 = BorderRadius.circular(10);
  static final BorderRadius r12 = BorderRadius.circular(12);
  static final BorderRadius r14 = BorderRadius.circular(14);
  static final BorderRadius r16 = BorderRadius.circular(16);
  static final BorderRadius rFull = BorderRadius.circular(999);

  static const BorderSide subtle = BorderSide(
    color: EnterpriseColors.borderLight,
    width: 1.0,
  );
}

abstract class EnterpriseShadows {
  // Soft 1dp elevation for clean enterprise depth
  static const List<BoxShadow> elevation1 = [
    BoxShadow(
      color: Color(0x0A0F172A), // 4% opacity slate
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x050F172A), // 2% opacity slate
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  // Hover or modal elevation
  static const List<BoxShadow> elevation2 = [
    BoxShadow(
      color: Color(0x120F172A), // 7% opacity slate
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  // Elevated Persistent Bottom Sheet Shadow (Upward Shadow)
  static const List<BoxShadow> bottomBarShadow = [
    BoxShadow(
      color: Color(0x0F0F172A),
      blurRadius: 20,
      offset: Offset(0, -5),
    ),
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 6,
      offset: Offset(0, -2),
    ),
  ];
}

abstract class EnterpriseSpacings {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
}
