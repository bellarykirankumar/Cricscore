import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
//  CricScore Shared Widgets
// ─────────────────────────────────────────────────────────────

// ── App Card ──────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;
  final EdgeInsets? padding;

  const AppCard({
    super.key, required this.child,
    this.onTap, this.borderColor, this.backgroundColor, this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.accent.withOpacity(0.05),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Primary Button ────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? color;

  const PrimaryButton({
    super.key, required this.label,
    this.onPressed, this.loading = false,
    this.icon, this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.accent,
          foregroundColor: AppColors.textOnAccent,
          disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAccent),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textOnAccent)),
              ],
            ),
      ),
    );
  }
}

// ── Secondary Button ──────────────────────────────────────────
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const SecondaryButton({ super.key, required this.label, this.onPressed });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;

  const StatusBadge({
    super.key, required this.label,
    required this.color, required this.bgColor,
  });

  factory StatusBadge.live() => const StatusBadge(
    label: 'LIVE', color: AppColors.wicket, bgColor: AppColors.wicketFaint,
  );

  factory StatusBadge.active() => const StatusBadge(
    label: 'Active', color: AppColors.accent, bgColor: AppColors.accentFaint,
  );

  factory StatusBadge.upcoming() => const StatusBadge(
    label: 'Upcoming', color: AppColors.ball, bgColor: AppColors.ballFaint,
  );

  factory StatusBadge.completed() => const StatusBadge(
    label: 'Completed', color: AppColors.textSecondary, bgColor: AppColors.bgElevated,
  );

  factory StatusBadge.forStatus(String status) {
    switch (status) {
      case 'in_progress': return StatusBadge.active();
      case 'upcoming':    return StatusBadge.upcoming();
      case 'completed':   return StatusBadge.completed();
      default:            return StatusBadge.upcoming();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'Inter', fontSize: 11,
        fontWeight: FontWeight.w700, color: color,
      )),
    );
  }
}

// ── Role Badge ────────────────────────────────────────────────
class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge({ super.key, required this.role });

  @override
  Widget build(BuildContext context) {
    final color = role == 'admin' ? AppColors.ball
      : role == 'scorer' ? AppColors.accent
      : AppColors.textSecondary;
    final bg = role == 'admin' ? AppColors.ballFaint
      : role == 'scorer' ? AppColors.accentFaint
      : AppColors.bgElevated;
    final label = role == 'admin' ? 'Admin'
      : role == 'scorer' ? 'Scorer'
      : 'Viewer';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'Inter', fontSize: 11,
        fontWeight: FontWeight.w700, color: color,
      )),
    );
  }
}

// ── Loading Screen ────────────────────────────────────────────
class LoadingScreen extends StatelessWidget {
  final String? message;
  const LoadingScreen({ super.key, this.message });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, style: AppTextStyles.caption),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Error Screen ──────────────────────────────────────────────
class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorScreen({ super.key, required this.message, this.onRetry });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.wicket, size: 48),
              const SizedBox(height: 16),
              Text(message, style: AppTextStyles.body, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                PrimaryButton(label: 'Try again', onPressed: onRetry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key, required this.emoji, required this.title,
    this.subtitle, this.actionLabel, this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: AppTextStyles.caption, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel({ super.key, required this.text, this.trailing });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: AppTextStyles.label),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── App Text Field ────────────────────────────────────────────
class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final Widget? suffix;

  const AppTextField({
    super.key, required this.label, this.hint,
    required this.controller, this.obscureText = false,
    this.keyboardType, this.validator, this.maxLines = 1, this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

// ── Team Avatar ───────────────────────────────────────────────
class TeamAvatar extends StatelessWidget {
  final String shortName;
  final Color color;
  final Color bgColor;
  final double size;

  const TeamAvatar({
    super.key, required this.shortName,
    required this.color, required this.bgColor,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Center(
        child: Text(
          shortName.length > 3 ? shortName.substring(0, 3) : shortName,
          style: TextStyle(
            fontFamily: 'Inter', fontSize: size * 0.28,
            fontWeight: FontWeight.w800, color: color,
          ),
        ),
      ),
    );
  }
}

// ── Live Indicator ────────────────────────────────────────────
class LiveIndicator extends StatefulWidget {
  const LiveIndicator({ super.key });
  @override
  State<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _anim,
          child: Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.wicket,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text('LIVE', style: AppTextStyles.label.copyWith(color: AppColors.wicket)),
      ],
    );
  }
}

// ── Score Header ──────────────────────────────────────────────
class ScoreHeader extends StatelessWidget {
  final String teamName;
  final int runs;
  final int wickets;
  final String overs;
  final double crrr;
  final int? target;
  final double? rrr;
  final int? projected;
  final int maxOvers;

  const ScoreHeader({
    super.key, required this.teamName,
    required this.runs, required this.wickets,
    required this.overs, required this.crrr,
    this.target, this.rrr, this.projected, required this.maxOvers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(teamName, style: AppTextStyles.caption),
                Text(
                  '$runs/$wickets',
                  style: AppTextStyles.scoreDisplay,
                ),
                Text(
                  '$overs ov  ·  CRR ${crrr.toStringAsFixed(2)}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          if (target != null)
            _InfoBox(
              top:    'Target $target',
              middle: '${target! - runs}',
              bottom: 'RRR ${rrr?.toStringAsFixed(1) ?? "-"}',
              middleColor: AppColors.ball,
            )
          else
            _InfoBox(
              top:    'Projected',
              middle: '${projected ?? 0}',
              bottom: 'off $maxOvers ov',
              middleColor: AppColors.accent,
            ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String top, middle, bottom;
  final Color middleColor;
  const _InfoBox({ required this.top, required this.middle, required this.bottom, required this.middleColor });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(top, style: AppTextStyles.tiny),
          const SizedBox(height: 2),
          Text(middle, style: AppTextStyles.h2.copyWith(color: middleColor, fontSize: 26)),
          const SizedBox(height: 2),
          Text(bottom, style: AppTextStyles.tiny),
        ],
      ),
    );
  }
}

// ── Ball Pip ──────────────────────────────────────────────────
class BallPip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;

  const BallPip({
    super.key, required this.label,
    required this.color, required this.bgColor,
  });

  factory BallPip.fromDelivery(dynamic delivery) {
    final isWicket = delivery['isWicket'] as bool? ?? false;
    final extras   = delivery['extras'];
    final runs     = (delivery['runs']?['batsman'] as num?)?.toInt() ?? 0;

    if (isWicket) return const BallPip(label: 'W', color: AppColors.wicket, bgColor: AppColors.wicketFaint);
    if (extras != null) {
      final type = extras['type'] as String? ?? '';
      if (type == 'wide')    return const BallPip(label: 'Wd', color: AppColors.ball, bgColor: AppColors.ballFaint);
      if (type == 'no_ball') return const BallPip(label: 'Nb', color: AppColors.ball, bgColor: AppColors.ballFaint);
    }
    if (runs == 6) return const BallPip(label: '6', color: AppColors.six,  bgColor: AppColors.sixFaint);
    if (runs == 4) return const BallPip(label: '4', color: AppColors.four, bgColor: AppColors.fourFaint);
    if (runs == 0) return const BallPip(label: '•', color: AppColors.textMuted, bgColor: AppColors.bgElevated);
    return BallPip(label: '$runs', color: AppColors.textPrimary, bgColor: AppColors.bgElevated);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: bgColor,
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Center(
        child: Text(label, style: TextStyle(
          fontFamily: 'Inter', fontSize: 11,
          fontWeight: FontWeight.w800, color: color,
        )),
      ),
    );
  }
}
