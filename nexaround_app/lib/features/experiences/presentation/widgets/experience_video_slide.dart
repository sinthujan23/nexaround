import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_fitted_photo.dart';
import 'package:video_player/video_player.dart';

/// One video slide in a package's gallery, behaving like the video on a
/// product page: plays by itself, muted, as soon as it is the visible slide,
/// pauses when swiped away and starts again from the top when swiped back.
///
/// A tap toggles play/pause; the speaker button toggles sound. The video fills
/// the 4:3 header like the photos, cropped to the frame rather than shown with
/// bars, so a phone-shot portrait clip shows its middle.
class ExperienceVideoSlide extends StatefulWidget {
  final String url;

  /// Whether this is the slide currently on screen.
  final bool active;

  /// Shown at once, before the first video frame arrives (the package's cover
  /// photo), so the slide is never a black box while the video starts.
  final String? posterUrl;

  const ExperienceVideoSlide({
    super.key,
    required this.url,
    required this.active,
    this.posterUrl,
  });

  @override
  State<ExperienceVideoSlide> createState() => _ExperienceVideoSlideState();
}

class _ExperienceVideoSlideState extends State<ExperienceVideoSlide>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _muted = true;
  // The viewer paused it by tapping; keep it paused until they say otherwise.
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      // The slide may have been swiped far away (and disposed) meanwhile.
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0.0 : 1.0);
      if (!mounted) return;
      setState(() {});
      _syncPlayback();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant ExperienceVideoSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (!widget.active) {
        // Leaving: next time it is shown it plays from the start again.
        _userPaused = false;
        _controller?.seekTo(Duration.zero);
      }
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPlayback();
    } else {
      _controller?.pause();
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active && !_userPaused) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _userPaused = true;
      controller.pause();
    } else {
      _userPaused = false;
      controller.play();
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _muted = !_muted);
    controller.setVolume(_muted ? 0.0 : 1.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_failed) {
      return Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.videocam_off_rounded,
              size: 48, color: AppColors.textMuted),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (widget.posterUrl != null)
            ExperienceFittedPhoto(
              url: widget.posterUrl!,
              headers: PlaceImageHelper.headersFor(widget.posterUrl),
            ),
          const Center(child: _SlideSpinner()),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          // Fills the frame like the photos do; the edges of a clip of another
          // shape are cropped rather than shown as bars.
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          // A spinner when playback stalls waiting for more of the stream; the
          // play icon only while paused, so a tap-to-pause is visibly a pause.
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.isBuffering
                ? const Center(child: _SlideSpinner())
                : value.isPlaying
                ? const SizedBox.shrink()
                : Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 36, color: Colors.white),
                    ),
                  ),
          ),
          Positioned(
            right: 14,
            bottom: 14,
            child: GestureDetector(
              onTap: _toggleMute,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideSpinner extends StatelessWidget {
  const _SlideSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 28,
      height: 28,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
    );
  }
}
