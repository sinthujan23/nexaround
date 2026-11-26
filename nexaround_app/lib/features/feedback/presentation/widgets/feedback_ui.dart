import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';

/// The shared look of the feedback screens (redesign, 2026-11-26): the form,
/// My feedback, the quarterly survey and the quick ratings.
class FeedbackUi {
  FeedbackUi._();

  static const ink = Color(0xFF14201F);
  static const sub = Color(0xFF5B6B6A);
  static const mute = Color(0xFF8A9796);
  static const line = Color(0xFFE4EAE9);
  static const bg = Color(0xFFF5F7F7);
  static const teal2 = Color(0xFF0E9A8F);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [FeedbackVocab.tealDark, FeedbackVocab.teal, teal2],
    stops: [0, 0.6, 1],
  );

  /// A text field with no fill and no border of its own, so the screen's one
  /// box is the only box. The app theme gives every field a grey fill and an
  /// outline; inside our own box that showed as a second box ("double line"),
  /// so every border is switched off here, not just `border`.
  static InputDecoration plainInput(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: mute, height: 1.45),
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        counterText: '',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      );

  /// A lighter shade of [c], for the top of an icon square's gradient.
  static Color light(Color c) => Color.lerp(c, Colors.white, 0.3)!;
}

/// The teal gradient button at the bottom of each screen.
class FeedbackPrimaryButton extends StatelessWidget {
  const FeedbackPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.iconAfter = false,
    this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final bool iconAfter;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final Widget? lead = busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : (icon == null ? null : Icon(icon, size: 20, color: Colors.white));
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled || busy ? 1 : 0.45,
          child: Container(
            height: 52,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: FeedbackUi.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? const [BoxShadow(color: Color(0x40005E60), blurRadius: 20, offset: Offset(0, 10))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (lead != null && !iconAfter) ...[lead, const SizedBox(width: 8)],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                if (lead != null && iconAfter) ...[const SizedBox(width: 8), lead],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon button for the top bars (back, close).
class FeedbackCircleButton extends StatelessWidget {
  const FeedbackCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.background = FeedbackUi.bg,
    this.label,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, size: 20, color: FeedbackUi.ink),
        ),
      ),
    );
  }
}

/// "YOUR MESSAGE ........ 86 / 5000": a small caps label over a block.
class FeedbackSectionLabel extends StatelessWidget {
  const FeedbackSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(children: [
        Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: FeedbackUi.mute)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: FeedbackUi.mute)),
      ]),
    );
  }
}

/// The coloured rounded square with a message type's icon.
class FeedbackTypeIcon extends StatelessWidget {
  const FeedbackTypeIcon({super.key, required this.kind, this.size = 40});

  final FeedbackKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.33),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FeedbackUi.light(kind.color), kind.color],
        ),
      ),
      child: Icon(kind.icon, size: size * 0.55, color: Colors.white),
    );
  }
}

/// The teal tick with a soft glow and a little confetti, for thank-you
/// screens.
class FeedbackSuccessBadge extends StatelessWidget {
  const FeedbackSuccessBadge({super.key});

  @override
  Widget build(BuildContext context) {
    Widget dot(double size, Color color, {double radius = 99}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
        );
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0xFFDDF6F2), Color(0xFFEEFAF8), Color(0x00FFFFFF)], stops: [0, 0.6, 1]),
            ),
          ),
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [FeedbackUi.teal2, FeedbackVocab.tealDark]),
              boxShadow: [BoxShadow(color: Color(0x52005E60), blurRadius: 28, offset: Offset(0, 14))],
            ),
            child: const Icon(Icons.check_rounded, size: 46, color: Colors.white),
          ),
          Positioned(left: 8, top: 22, child: dot(9, const Color(0xFFF59E0B))),
          Positioned(right: 10, top: 14, child: Transform.rotate(angle: 0.5, child: dot(7, const Color(0xFFEC4899), radius: 2))),
          Positioned(right: 2, bottom: 30, child: dot(8, FeedbackVocab.mint)),
          Positioned(left: 18, bottom: 16, child: dot(6, const Color(0xFF3B82F6), radius: 2)),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1), duration: 420.ms, curve: Curves.easeOutBack);
  }
}
