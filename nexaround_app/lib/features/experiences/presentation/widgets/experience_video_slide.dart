import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_fitted_photo.dart';
import 'package:video_player/video_player.dart';

/// Videos a viewer has already streamed, kept on the phone so the next visit
/// plays at once. Separate from the photo cache so a few large clips can't
/// push out hundreds of photos, and capped so they can't fill the phone.
final CacheManager _videoCache = CacheManager(
  Config(
    'experienceVideos',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 10,
  ),
);

/// One video slide in a package's gallery, behaving like the video on a
/// product page: plays by itself, muted, as soon as it is the visible slide,
/// pauses when swiped away and starts again from the top when swiped back.
///
/// Until the video is actually playing the slide is just the cover photo, with
/// no spinner, so it reads as a photo rather than as something buffering; the
/// video fades in over it once frames arrive. The player stays alive while the
/// page is open, so swiping away and back does not start the download again.
///
/// The first visit streams the video (the server answers range requests and
/// uploads are faststart), so playback starts long before the whole file has
/// arrived. Once the stream has reached the end, a copy is saved to
/// [_videoCache] and later visits play that file instead.
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
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _muted = true;
  // The viewer paused it by tapping; keep it paused until they say otherwise.
  bool _userPaused = false;
  // Frames are on screen: the poster has faded out and the controls show.
  bool _showVideo = false;
  // Streaming from the server and not yet copied to the phone.
  bool _needsCaching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    FileInfo? cached;
    try {
      cached = await _videoCache.getFileFromCache(widget.url);
    } catch (_) {
      // A broken cache entry just means streaming it again.
    }
    if (!mounted) return;

    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = cached != null
        ? VideoPlayerController.file(cached.file, videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(
            Uri.parse(widget.url),
            videoPlayerOptions: options,
          );
    _controller = controller;
    _needsCaching = cached == null;
    controller.addListener(_onValue);
    try {
      await controller.initialize();
      // The page may have been closed (and the slide disposed) meanwhile.
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

  void _onValue() {
    final value = _controller!.value;
    // `isPlaying` turns true as soon as play() is called; a moving position
    // means frames are really arriving, so only then does the poster go.
    if (!_showVideo && value.isPlaying && value.position > Duration.zero) {
      setState(() => _showVideo = true);
    }
    // Copy it to the phone only once the stream has delivered the whole video,
    // so the second download never competes with playback for bandwidth.
    if (_needsCaching && _bufferedToEnd(value)) {
      _needsCaching = false;
      // Fire and forget: a failed copy just means streaming it next time.
      _videoCache.downloadFile(widget.url).ignore();
    }
  }

  bool _bufferedToEnd(VideoPlayerValue value) {
    final duration = value.duration;
    if (duration <= Duration.zero) return false;
    final end = duration - const Duration(seconds: 1);
    return value.buffered.any((range) => range.end >= end);
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
    // Before frames show the slide is just the poster; a tap there would
    // pause a video the viewer has not seen yet.
    if (controller == null || !_showVideo) return;
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
    _controller?.removeListener(_onValue);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller;
    final poster = widget.posterUrl == null
        ? null
        : ExperienceFittedPhoto(
            url: widget.posterUrl!,
            headers: PlaceImageHelper.headersFor(widget.posterUrl),
          );

    if (_failed) {
      // A video that will not play leaves the slide as the cover photo.
      return poster ??
          Container(
            color: AppColors.surfaceVariant,
            child: const Center(
              child: Icon(Icons.videocam_off_rounded,
                  size: 48, color: AppColors.textMuted),
            ),
          );
    }

    // Non-null once the player can draw frames.
    final ready = controller != null && controller.value.isInitialized
        ? controller
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          // Fills the frame like the photos do; the edges of a clip of another
          // shape are cropped rather than shown as bars.
          if (ready != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: ready.value.size.width,
                height: ready.value.size.height,
                child: VideoPlayer(ready),
              ),
            ),
          if (poster != null)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showVideo ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 350),
                child: poster,
              ),
            ),
          // Once the video shows: a spinner when playback stalls waiting for
          // more of the stream, and the play icon only while paused, so a
          // tap-to-pause is visibly a pause.
          if (ready != null && _showVideo)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: ready,
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
          if (ready != null && _showVideo)
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
