import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  CricScore Design System — Royal Blue
// ─────────────────────────────────────────────────────────────

class AppColors {
  // Backgrounds — midnight blue layers
  static const bg           = Color(0xFF080C1F);
  static const bgCard       = Color(0xFF0D1230);
  static const bgElevated   = Color(0xFF131A3D);

  // Accent — electric blue
  static const accent       = Color(0xFF3B82F6);
  static const accentFaint  = Color(0x203B82F6);

  // Ball — amber
  static const ball         = Color(0xFFF59E0B);
  static const ballFaint    = Color(0x20F59E0B);

  // Events
  static const wicket       = Color(0xFFEF4444);
  static const wicketFaint  = Color(0x20EF4444);
  static const four         = Color(0xFF60A5FA);  // light blue
  static const six          = Color(0xFFF59E0B);  // amber

  // Text
  static const text         = Color(0xFFEEF2FF);
  static const text2        = Color(0xFF94A3B8);
  static const text3        = Color(0xFF475569);
  static const textOnAcc    = Color(0xFFFFFFFF);

  // Borders
  static const border       = Color(0xFF1E2D5A);
  static const borderDim    = Color(0xFF0F1535);

  // Card gradient stops
  static const cardGradTop  = Color(0xFF131A3D);
  static const cardGradBot  = Color(0xFF0D1230);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.ball,
      surface: AppColors.bgCard,
      error: AppColors.wicket,
    ),
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgCard,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w800,
        color: AppColors.text, fontFamily: 'Inter',
        letterSpacing: 0.3,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.text2),
      hintStyle: const TextStyle(color: AppColors.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAcc,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.4,
        ),
        elevation: 0,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border, thickness: 1, space: 1,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.text2,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w800, fontFamily: 'Inter', letterSpacing: 0.3,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500, fontFamily: 'Inter',
      ),
      dividerColor: AppColors.border,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgElevated,
      contentTextStyle: const TextStyle(color: AppColors.text, fontFamily: 'Inter'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ── Shared Widgets ────────────────────────────────────────────

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;
  final EdgeInsets? padding;
  final Color? color; // pass a solid color to override gradient

  const AppCard({
    super.key, required this.child,
    this.onTap, this.borderColor, this.padding, this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        gradient: color == null
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.cardGradTop, AppColors.cardGradBot],
              )
            : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key, required this.label,
    this.onTap, this.loading = false, this.icon,
  });

  @override Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        child: loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnAcc))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Text(label),
            ]),
      ),
    );
  }
}

class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const OutlineButton({super.key, required this.label, this.onTap, this.color});

  @override Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return SizedBox(
      width: double.infinity, height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800,
          color: c, letterSpacing: 0.4,
        )),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800,
        color: color, letterSpacing: 0.8,
      )),
    );
  }
}

class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});
  @override State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.wicketFaint,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            color: AppColors.wicket.withOpacity(_anim.value),
            shape: BoxShape.circle,
          )),
          const SizedBox(width: 5),
          const Text('LIVE', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800,
            color: AppColors.wicket, letterSpacing: 0.8,
          )),
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(children: [
        Text(title.toUpperCase(), style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800,
          color: AppColors.text2, letterSpacing: 1.5,
        )),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class TeamAvatar extends StatelessWidget {
  final String shortName;
  final Color color;
  final double size;

  const TeamAvatar({
    super.key, required this.shortName,
    this.color = AppColors.accent, this.size = 44,
  });

  @override Widget build(BuildContext context) {
    final display = shortName.length > 3 ? shortName.substring(0, 3) : shortName;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.45), width: 1.5),
      ),
      child: Center(child: Text(display, style: TextStyle(
        fontSize: size * 0.28, fontWeight: FontWeight.w900,
        color: color, letterSpacing: 0.5,
      ))),
    );
  }
}

class BallPip extends StatelessWidget {
  final String label;
  final bool isWicket;
  final bool isExtra;
  final bool isFour;
  final bool isSix;

  const BallPip({
    super.key, required this.label,
    this.isWicket = false, this.isExtra = false,
    this.isFour = false, this.isSix = false,
  });

  @override Widget build(BuildContext context) {
    Color bg, fg;
    if (isWicket)     { bg = AppColors.wicketFaint; fg = AppColors.wicket; }
    else if (isExtra) { bg = AppColors.ballFaint;   fg = AppColors.ball; }
    else if (isSix)   { bg = AppColors.six.withOpacity(0.15); fg = AppColors.six; }
    else if (isFour)  { bg = AppColors.four.withOpacity(0.15); fg = AppColors.four; }
    else              { bg = AppColors.bgElevated;  fg = AppColors.text2; }

    return Container(
      width: 32, height: 32,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle,
        border: Border.all(color: fg.withOpacity(0.4))),
      child: Center(child: Text(label, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w800, color: fg,
      ))),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorScreen({super.key, required this.message, this.onRetry});

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('😕', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.text2, fontSize: 15)),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Try again'),
            ),
          ],
        ]),
      )),
    );
  }
}

// Helpers
String ballsToOvers(int balls) => '${balls ~/ 6}.${balls % 6}';
String scoreFmt(int runs, int wickets) => '$runs/$wickets';
