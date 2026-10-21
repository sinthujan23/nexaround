import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../data/models/travel_story.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'official_story_widgets.dart';
import 'story_photo_preview.dart';

class TravelStoryCard extends StatefulWidget {
  final TravelStory story;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback? onLocationTap;
  final VoidCallback? onTap;
  final void Function(int imageIndex)? onImageTap;

  /// How many TravelBytes this card stands for. All of them share the first
  /// card of the row, which shows the first; above one, it says how many and
  /// the edge of a second card shows behind it.
  final int travelByteCount;

  /// Puts another TravelByte on this card, at random. Set by the home row on
  /// its TravelByte card when it holds two or more; shows the round green
  /// button on the photo's bottom edge.
  final VoidCallback? onShuffle;

  const TravelStoryCard({
    super.key,
    required this.story,
    required this.onLikeTap,
    required this.onCommentTap,
    this.onLocationTap,
    this.onTap,
    this.onImageTap,
    this.travelByteCount = 1,
    this.onShuffle,
  });

  @override
  State<TravelStoryCard> createState() => _TravelStoryCardState();
}

class _TravelStoryCardState extends State<TravelStoryCard>
    with SingleTickerProviderStateMixin {
  bool _localLiked = false;
  int _localLikesCount = 0;

  // Runs when the shuffle button has put another TravelByte on the card: it
  // comes forward from the card edge behind, and the button's arrows turn
  // once. At rest (1) nothing is moved.
  late final AnimationController _deal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _localLiked = widget.story.isLiked;
    _localLikesCount = widget.story.likesCount;
  }

  @override
  void didUpdateWidget(covariant TravelStoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A shuffle keeps this card and swaps its story, so the like state has to
    // follow the story even when both happen to have the same count.
    final otherStory = oldWidget.story.id != widget.story.id;
    if (otherStory ||
        oldWidget.story.isLiked != widget.story.isLiked ||
        oldWidget.story.likesCount != widget.story.likesCount) {
      setState(() {
        _localLiked = widget.story.isLiked;
        _localLikesCount = widget.story.likesCount;
      });
    }
    if (otherStory && widget.onShuffle != null) _deal.forward(from: 0);
  }

  @override
  void dispose() {
    _deal.dispose();
    super.dispose();
  }

  Color _getCategoryColor(String category) {
    if (category.contains('Hidden')) return Colors.purple;
    if (category.contains('Offbeat')) return Colors.orange;
    if (category.contains('Secret')) return AppColors.brandGreen;
    if (category.contains('Scenic')) return Colors.blue;
    return Colors.teal;
  }

  Widget _buildImage(String url, int index, List<String> allUrls) {
    return GestureDetector(
      onTap: () {
        if (widget.onImageTap != null) {
          widget.onImageTap!(index);
        } else if (widget.onTap != null) {
          widget.onTap!();
        }
      },
      child: _buildImageContent(url),
    );
  }

  /// While a photo loads: its blurred preview when the server sent one
  /// (older cached stories have none), otherwise a spinner.
  Widget _loadingPhoto(String url) {
    final preview = widget.story.imagePreviews[url];
    if (preview != null) return StoryPhotoPreview(preview: preview);
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.brandGreen,
          ),
        ),
      ),
    );
  }

  static const double _textSize = 11.5;
  static const double _textLineHeight = 1.4;

  /// [text] with as many whole lines as fit the space left between the photo
  /// and the footer, at most [maxLines]. The card has a fixed height, so a
  /// header that wraps or a larger system font size shortens the text
  /// instead of pushing the footer out of the card.
  Widget _inSpaceLeft({
    required int maxLines,
    required EdgeInsets padding,
    required Widget Function(int lines) text,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final line =
            MediaQuery.textScalerOf(context).scale(_textSize) * _textLineHeight;
        // The half pixel absorbs rounding: two 16.1 px lines fit in 32.0.
        final lines = math.min(
          maxLines,
          ((box.maxHeight - padding.vertical + 0.5) / line).floor(),
        );
        if (lines < 1) return const SizedBox.shrink();
        return Padding(padding: padding, child: text(lines));
      },
    );
  }

  Widget _buildImageContent(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        // Story photos are user camera uploads and can be 3000px+ wide, which
        // decodes to tens of MB of bitmap each. The grid never draws them
        // larger than the card (~360dp at 3x DPR), and tapping through opens
        // the full-screen viewer, which loads the original untouched.
        memCacheWidth: 1080,
        placeholder: (_, __) => _loadingPhoto(url),
        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
      );
    } else if (url.startsWith('/static/')) {
      final fullUrl = '${ApiConstants.baseUrl}$url';
      return CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        memCacheWidth: 1080, // card is ~360dp wide at 3x DPR
        placeholder: (_, __) => _loadingPhoto(url),
        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: AppColors.surfaceVariant),
        );
      } else {
        final fullUrl = url.startsWith('/')
            ? '${ApiConstants.baseUrl}$url'
            : url;
        return CachedNetworkImage(
          imageUrl: fullUrl,
          fit: BoxFit.cover,
          memCacheWidth: 1080, // card is ~360dp wide at 3x DPR
          placeholder: (_, __) => _loadingPhoto(url),
          errorWidget: (_, __, ___) =>
              Container(color: AppColors.surfaceVariant),
        );
      }
    }
  }


  Widget _buildImageGrid(List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();

    final images = urls.take(3).toList();
    final isSingle = images.length == 1;
    final isDouble = images.length == 2;

    if (isSingle) {
      return _buildImage(images[0], 0, urls);
    }

    if (isDouble) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildImage(images[0], 0, urls)),
          const SizedBox(width: 2),
          Expanded(child: _buildImage(images[1], 1, urls)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 2, child: _buildImage(images[0], 0, urls)),
        const SizedBox(width: 2),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildImage(images[1], 1, urls)),
              const SizedBox(height: 2),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImage(images[2], 2, urls),
                    if (urls.length > 3)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        alignment: Alignment.center,
                        child: Text(
                          '+${urls.length - 3}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _getCategoryColor(widget.story.category);
    final allUrls = widget.story.imageUrls.isNotEmpty
        ? widget.story.imageUrls
        : (widget.story.imageUrl.isNotEmpty
              ? [widget.story.imageUrl]
              : <String>[]);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: _withStackEdge(_dealing(Container(
        width: 280,
        margin: const EdgeInsets.only(right: 18, bottom: 8, top: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          // A TravelByte stands apart from travellers' stories by its
          // border in the app's green.
          border: widget.story.isOfficial
              ? Border.all(color: AppColors.brandGreen, width: 2.0)
              : Border.all(
                  color: AppColors.border.withOpacity(0.8),
                  width: 1.0,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info header
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (widget.story.isOfficial)
                      const OfficialAvatar(radius: 16)
                    else
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[200],
                      backgroundImage:
                          widget.story.userAvatar.startsWith('http')
                          ? CachedNetworkImageProvider(widget.story.userAvatar)
                          : null,
                      child: !widget.story.userAvatar.startsWith('http')
                          ? const Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.story.isOfficial)
                            OfficialName(
                              name: widget.story.userName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            )
                          else
                          BlocBuilder<AuthBloc, AuthState>(
                            builder: (context, authState) {
                              String display = widget.story.userName;
                              if (display.trim().isEmpty || display.trim().toLowerCase() == 'anonymous') {
                                if (authState is AuthAuthenticated) {
                                  display = authState.user.displayName.isNotEmpty && authState.user.displayName.toLowerCase() != 'anonymous' 
                                      ? authState.user.displayName 
                                      : (authState.user.email.isNotEmpty ? authState.user.email.split('@')[0] : 'Explorer');
                                } else {
                                  display = 'Explorer';
                                }
                              }
                              return Text(
                                display,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                          Text(
                            widget.travelByteCount > 1
                                ? '${_timeAgo(widget.story.createdAt)} · ${widget.travelByteCount} TravelBytes'
                                : _timeAgo(widget.story.createdAt),
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Category Tag and Spend
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Capped so a long label ("CHINA · FURONG TOWN") can't
                        // squeeze the name into many lines.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: catColor.withOpacity(0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              widget.story.category,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: catColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (widget.story.isJournal && widget.story.totalSpend > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              '${widget.story.spendCurrency} ${widget.story.totalSpend.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Photo and text. The shuffle button sits across the photo's
              // bottom edge: it is laid over both, so all of it takes taps.
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Post image
                        SizedBox(
                          height: 240,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildImageGrid(allUrls),
                              // Location Overlay Tag. Bounded to the photo's width so a
                              // long place name ellipsizes instead of pushing the
                              // distance off the card.
                              Positioned(
                                bottom: 8,
                                left: 8,
                                right: widget.onShuffle != null ? 56 : 8,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: GestureDetector(
                                    onTap: widget.onLocationTap,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        color: Colors.black.withOpacity(0.6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.location_on,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                widget.story.locationName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            // Capped, so at a large text size
                                            // it can't push the tag past the
                                            // photo's edge.
                                            if (widget.story.distanceM != null)
                                              ConstrainedBox(
                                                constraints: const BoxConstraints(maxWidth: 110),
                                                child: Text(
                                                  '  ·  ${storyDistanceLabel(widget.story.distanceM!)}',
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.story.imageUrls.length > 1)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.layers_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Story description, in the space left above the
                        // footer (_inSpaceLeft). An official story's intro
                        // stops at two lines: its footer carries the "See more"
                        // tab.
                        Expanded(
                          child: _inSpaceLeft(
                            maxLines: widget.story.hasArticle ? 2 : 3,
                            padding: EdgeInsets.fromLTRB(
                              12, 10, widget.onShuffle != null ? 54 : 12, 6,
                            ),
                            text: (lines) => widget.story.hasArticle
                                ? Text(
                                    widget.story.description,
                                    style: const TextStyle(
                                      fontSize: _textSize,
                                      height: _textLineHeight,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: lines,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: widget.story.description.length > 95
                                              ? '${widget.story.description.substring(0, 92)}...'
                                              : widget.story.description,
                                          style: const TextStyle(
                                            fontSize: _textSize,
                                            height: _textLineHeight,
                                            fontWeight: FontWeight.w400,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        if (widget.story.description.length > 95)
                                          const TextSpan(
                                            text: ' see more',
                                            style: TextStyle(
                                              fontSize: _textSize,
                                              height: _textLineHeight,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.brandGreen,
                                            ),
                                          ),
                                      ],
                                    ),
                                    maxLines: lines,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onShuffle != null)
                      Positioned(top: 240 - 22, right: 10, child: _shuffleButton()),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.border),

              // Social actions footer
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    // Like button
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          if (_localLiked) {
                            _localLiked = false;
                            _localLikesCount--;
                          } else {
                            _localLiked = true;
                            _localLikesCount++;
                          }
                          // Kept on the story too, as the viewer does, so a
                          // TravelByte shuffled away and back shows the like.
                          widget.story.isLiked = _localLiked;
                          widget.story.likesCount = _localLikesCount;
                        });
                        widget.onLikeTap();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                                _localLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 16,
                                color: _localLiked
                                    ? Colors.red
                                    : AppColors.textTertiary,
                              )
                              .animate(target: _localLiked ? 1.0 : 0.0)
                              .scale(
                                begin: const Offset(1.0, 1.0),
                                end: const Offset(1.3, 1.3),
                                curve: Curves.elasticOut,
                                duration: 350.ms,
                              ),
                          const SizedBox(width: 4),
                          Text(
                            '$_localLikesCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Comment button
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onCommentTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.story.comments.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.story.hasArticle)
                      // Opens the long read of the TravelByte on the card
                      // (the shuffle can put any of them here); that page
                      // ends with the way to all of them in Exclusive.
                      // Shrunk only if a large text size leaves it too
                      // little room.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ReadExperienceTab(
                              compact: true,
                              label: 'See more',
                              onTap: () => openStoryExperience(context, widget.story),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ))),
    );
  }

  /// [card] coming forward from the edge behind it while [_deal] runs.
  Widget _dealing(Widget card) {
    return AnimatedBuilder(
      animation: _deal,
      child: card,
      builder: (context, child) {
        if (_deal.value == 1) return child!;
        final t = Curves.easeOutCubic.transform(_deal.value);
        return Opacity(
          opacity: 0.2 + 0.8 * t,
          child: Transform.translate(
            offset: Offset(48 * (1 - t), 0),
            child: Transform.rotate(
              angle: 0.07 * (1 - t),
              child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
            ),
          ),
        );
      },
    );
  }

  /// The round green button that puts another TravelByte on the card. 36 px
  /// across in a 44 px tap area; its arrows turn once as the next one comes.
  Widget _shuffleButton() {
    return Semantics(
      button: true,
      label: 'Show another TravelByte',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onShuffle!();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.brandGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandGreenDark.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _deal,
                builder: (context, child) => Transform.rotate(
                  angle: Curves.easeOutCubic.transform(_deal.value) * 2 * math.pi,
                  child: child,
                ),
                child: const Icon(
                  Icons.shuffle_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Puts the edge of a second card behind [card] when it holds more than one
  /// TravelByte. The edge pokes out on the right, into the gap before the
  /// next card, so the row keeps its spacing.
  Widget _withStackEdge(Widget card) {
    if (widget.travelByteCount <= 1) return card;
    return Stack(
      // The card's own shadow reaches past the Stack's box; clipping it would
      // make this one card look different from the rest of the row.
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 18,
          bottom: 22,
          right: 8,
          width: 60,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              // Green like the TravelByte card in front of it.
              border: Border.all(color: AppColors.brandGreen.withOpacity(0.55), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
        card,
      ],
    );
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    final days = difference.inDays;

    if (days >= 365) {
      final years = (days / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    } else if (days >= 60) {
      final months = (days / 30).floor();
      return '$months months ago';
    } else if (days >= 30) {
      return '1 month ago';
    } else if (days >= 7) {
      final weeks = (days / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (days >= 1) {
      return days == 1 ? '1 day ago' : '$days days ago';
    } else if (difference.inHours >= 1) {
      return difference.inHours == 1 ? '1 hour ago' : '${difference.inHours} hours ago';
    } else if (difference.inMinutes >= 1) {
      return difference.inMinutes == 1 ? '1 min ago' : '${difference.inMinutes} mins ago';
    } else {
      return 'just now';
    }
  }
}

/// "800 m away", "3.2 km away", "250 km away".
String storyDistanceLabel(double metres) {
  if (metres < 100) return 'under 100 m away';
  if (metres < 1000) {
    return '${(metres / 50).round() * 50} m away';
  }
  final km = metres / 1000;
  if (km < 10) return '${km.toStringAsFixed(1)} km away';
  return '${km.round()} km away';
}
