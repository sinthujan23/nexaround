import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/app/theme/app_typography.dart';

/// Section header with optional eyebrow, title, subtitle, and trailing action.
class SectionHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: AppTypography.eyebrow),
                  const SizedBox(height: 6),
                ],
                Text(title, style: AppTypography.h2),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppTypography.bodySecondary),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Premium primary button with subtle press animation and layered shadow.
class PremiumButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;
  final Color? background;
  final Color? foreground;
  final EdgeInsetsGeometry? padding;

  const PremiumButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.background,
    this.foreground,
    this.padding,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final bg = enabled
        ? (widget.background ?? AppColors.primary)
        : AppColors.surfaceElevated;
    final fg = enabled
        ? (widget.foreground ?? Colors.white)
        : AppColors.textTertiary;

    final child = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.standard,
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadii.brMd,
          boxShadow: enabled ? AppShadows.button : null,
        ),
        child: Row(
          mainAxisSize:
              widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            else if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 10),
            ],
            if (!widget.loading)
              Text(
                widget.label,
                style: AppTypography.button.copyWith(color: fg),
              ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: child,
    );
  }
}

/// Soft rounded badge used for icon affordances inside cards / list tiles.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final bool filled;

  const IconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
    this.iconSize = 20,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? accent : accent.withOpacity(0.08),
        borderRadius: AppRadii.brSm,
        border: filled
            ? null
            : Border.all(color: accent.withOpacity(0.18), width: 0.8),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: filled ? Colors.white : accent,
      ),
    );
  }
}

/// Hairline divider that respects the theme color and adds breathing space.
class SoftDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  final double spacing;

  const SoftDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.spacing = AppSpacing.md,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing),
      child: Divider(
        height: 0.6,
        thickness: 0.6,
        color: AppColors.border,
        indent: indent,
        endIndent: endIndent,
      ),
    );
  }
}
