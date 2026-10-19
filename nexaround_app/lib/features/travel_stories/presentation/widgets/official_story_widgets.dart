import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/models/travel_story.dart';
import '../pages/story_experience_page.dart';

/// The pieces that mark a story the team posted as TravelByte: the logo in
/// place of a profile photo, the blue tick, and the "Read the experience" tab.

const Color kVerifiedBlue = Color(0xFF1D9BF0);

/// The nexARound pin mark on white, the size of a poster's avatar.
class OfficialAvatar extends StatelessWidget {
  final double radius;

  const OfficialAvatar({super.key, required this.radius});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(radius * 0.22),
        child: Image.asset('assets/images/logo_2.png', fit: BoxFit.contain),
      ),
    );
  }
}

/// The account name ("TravelByte") with the blue verified tick after it.
class OfficialName extends StatelessWidget {
  final String name;
  final TextStyle style;

  const OfficialName({super.key, required this.name, required this.style});

  @override
  Widget build(BuildContext context) {
    final size = (style.fontSize ?? 13) + 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 3),
        Icon(Icons.verified_rounded, size: size, color: kVerifiedBlue),
      ],
    );
  }
}

/// Opens the long read of an official story; completes when it is closed.
Future<void> openStoryExperience(BuildContext context, TravelStory story) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => StoryExperiencePage(story: story)),
  );
}

/// The pill on an official story that opens its long read. A light sweep
/// runs across it every few seconds so it reads as something to tap.
class ReadExperienceTab extends StatelessWidget {
  final VoidCallback onTap;

  /// Smaller, for the story card.
  final bool compact;

  const ReadExperienceTab({super.key, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 10.5 : 13.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.brandGreen, AppColors.brandGreenDark],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandGreen.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, size: fontSize + 3, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'Read the experience',
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, size: fontSize + 2, color: Colors.white)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveX(begin: 0, end: 3, duration: 700.ms, curve: Curves.easeInOut),
          ],
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            delay: 1200.ms,
            duration: 1400.ms,
            color: Colors.white.withValues(alpha: 0.55),
          ),
    );
  }
}
