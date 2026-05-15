import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';

/// Reusable glassmorphism card used throughout the app.
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? glowColor;
  final double blur;
  final VoidCallback? onTap;

  /// When true (default), tapping the card produces a subtle press animation.
  final bool pressFeedback;

  /// Elevation level — controls the base shadow stack.
  final GlassElevation elevation;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.glowColor,
    this.blur = 20,
    this.onTap,
    this.pressFeedback = true,
    this.elevation = GlassElevation.sm,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

enum GlassElevation { flat, sm, md, lg }

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  List<BoxShadow> get _baseShadow {
    switch (widget.elevation) {
      case GlassElevation.flat:
        return AppShadows.none;
      case GlassElevation.sm:
        return AppShadows.sm;
      case GlassElevation.md:
        return AppShadows.md;
      case GlassElevation.lg:
        return AppShadows.lg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final br = widget.borderRadius ?? AppRadii.brLg;

    final shadows = <BoxShadow>[
      ..._baseShadow,
      if (widget.glowColor != null) ...AppShadows.glow(widget.glowColor!),
    ];

    final card = AnimatedScale(
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      scale: _pressed ? 0.985 : 1.0,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.standard,
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: br,
          boxShadow: shadows,
        ),
        child: ClipRRect(
          borderRadius: br,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
            child: Container(
              padding: widget.padding ?? AppSpacing.cardPadding,
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: br,
                border: Border.all(
                  color: AppColors.glassBorder,
                  width: 0.6,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown:
          widget.pressFeedback ? (_) => setState(() => _pressed = true) : null,
      onTapUp:
          widget.pressFeedback ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.pressFeedback ? () => setState(() => _pressed = false) : null,
      child: card,
    );
  }
}

/// Neon-bordered container used for section highlights
class NeonBorderContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final BorderRadius? borderRadius;

  const NeonBorderContainer({
    super.key,
    required this.child,
    this.padding,
    this.color = AppColors.primary,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? AppRadii.brLg;
    return Container(
      padding: padding ?? AppSpacing.cardPadding,
      decoration: BoxDecoration(
        borderRadius: br,
        border: Border.all(color: color.withOpacity(0.28), width: 0.8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.08),
            color.withOpacity(0.02),
          ],
        ),
        boxShadow: [
          ...AppShadows.sm,
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Gradient text helper
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final TextAlign? textAlign;

  const GradientText({
    super.key,
    required this.text,
    this.style,
    this.gradient = AppColors.primaryGradient,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        textAlign: textAlign,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
