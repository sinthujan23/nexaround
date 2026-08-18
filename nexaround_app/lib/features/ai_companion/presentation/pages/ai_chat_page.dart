import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/services/permission_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';

class AiChatPage extends StatefulWidget {
  final String? initialPrompt;

  /// Optional context about a place the user is currently asking about.
  /// Expected keys: name, category, latitude, longitude.
  /// When provided, the chip bar shows Food / Shopping / Services buttons
  /// that fetch nearby venues around this place.
  final Map<String, dynamic>? placeContext;

  /// If set, the chat page auto-runs a nearby-places fetch for this category
  /// the moment it opens — used when the user taps a NEARBY tile in the AR
  /// detail card and lands here pre-filtered.
  final String? autoFetchCategoryId;
  final String? autoFetchCategoryLabel;

  const AiChatPage({
    super.key,
    this.initialPrompt,
    this.placeContext,
    this.autoFetchCategoryId,
    this.autoFetchCategoryLabel,
  });

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _showSuggestions = true;
  bool _isFetchingPlaces = false;
  String? _activeCategoryChip;
  // Resolved once so Neva can tailor answers to where the user actually is.
  String? _userArea;
  double? _userLat;
  double? _userLng;
  bool _locationResolved = false;
  final GeminiService _geminiService = GeminiService();

  static const List<Map<String, dynamic>> _nearbyCategories = [
    {'id': 'Food & Drink', 'label': 'Food', 'icon': Icons.restaurant_rounded},
    {'id': 'Shopping', 'label': 'Shopping', 'icon': Icons.shopping_bag_rounded},
    {
      'id': 'Experiences',
      'label': 'Services',
      'icon': Icons.miscellaneous_services_rounded,
    },
  ];

  bool get _hasPlaceContext {
    final ctx = widget.placeContext;
    return ctx != null && ctx['latitude'] != null && ctx['longitude'] != null;
  }

  static const String _nevaSystemPrompt = '''
You are Neva — a warm, witty, and effortlessly stylish FEMALE travel companion inside the NexAround app. Think of yourself as the user's smartest, most well-travelled girlfriend, the one who always knows the loveliest spots.

VOICE & PERSONALITY:
- Speak in the first person as a woman — confident, charming, caring, and a little playful. Like texting a close friend, never robotic or formal.
- You're an expert in travel, local food, culture, history, hidden gems, safety, budgeting, and itineraries — but you share it like a friend, not a search engine.

HOW TO FORMAT EVERY REPLY (this controls how beautiful it looks in the app, so follow it):
- Open with ONE short, friendly sentence.
- When you give options or tips, use a clean bullet list. Start each line with "* ", put the key phrase in **bold**, then a short, vivid description. Example:
  * **Cozy wine bar** — perfect for a relaxed, romantic evening. 🍷
  * **Lively rooftop** — great music and a buzzing crowd. ✨
- Keep it skimmable: short lines, no big walls of text.
- Use tasteful, feminine emojis NATURALLY — 1 to 3 per message, never one on every single line. Favourites: ✨🌸💫🌙💖🥂☕🛍️🗺️🌿. Never force them.
- Do NOT use markdown headings (#), tables, or code blocks — only short text, **bold**, and "* " bullets.
- When it feels natural, end with a warm, inviting question.

LOCATION AWARENESS:
- The user's current area and coordinates may be given to you in the context. When they are, tailor every idea and recommendation to THAT area and mention it naturally (e.g. "Since you're around Colombo, ...").
- For "ideas", "plans", "what to do" or "day out" style questions, suggest a few specific, realistic local spots or areas that fit — woven into your answer, not a raw list.
- Never ask the user where they are when their location is already provided in the context.
- If you don't recognise a specific place by name, never reply that you don't know it — give your best, genuinely useful take based on its category and the area, confidently and warmly.

WHAT YOU NEVER DO:
- Don't dump a long raw list of places unprompted — weave a few specific suggestions in naturally instead.
- Never give generic, copy-paste travel-blog answers — always be specific and personal.
- Never say you are an AI language model or mention Gemini/Google. You are simply Neva.

Your goal: make every traveller feel they have a brilliant, caring local friend who's got their back. 💖
''';

  final List<String> _quickPrompts = [
    '🌙 Safe night spots',
    '🍜 Authentic hoppers',
    '🏛 Hidden history',
    '💸 Local prices',
  ];

  @override
  void initState() {
    super.initState();
    // Kick off location resolution early so the very first answer is local.
    _resolveUserLocation();
    _messages.add(
      _ChatMessage(
        text:
            "Hey! I'm Neva ✨ Your personal travel companion. Whether you need hidden gems, local food tips, or a full itinerary — I've got you covered.\n\nWhat are we exploring today?",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    if (widget.initialPrompt != null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _sendMessage(widget.initialPrompt!);
      });
    }

    // If launched from an AR "NEARBY" tile, auto-run the matching fetch so the
    // user sees results immediately rather than having to tap a chip.
    if (widget.autoFetchCategoryId != null && _hasPlaceContext) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _fetchNearbyForCategory(
          widget.autoFetchCategoryId!,
          widget.autoFetchCategoryLabel ?? widget.autoFetchCategoryId!,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant AiChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The Neva tab lives inside the home IndexedStack, so this page stays
    // mounted and initState runs only once. When the AR "Ask Neva More" flow
    // pushes a fresh prompt/place into the already-live page, deliver it here
    // (otherwise the user would just see the default greeting).
    if (widget.initialPrompt != null &&
        widget.initialPrompt != oldWidget.initialPrompt) {
      _showSuggestions = false;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _sendMessage(widget.initialPrompt!);
      });
    }
    if (widget.autoFetchCategoryId != null &&
        widget.autoFetchCategoryId != oldWidget.autoFetchCategoryId &&
        _hasPlaceContext) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _fetchNearbyForCategory(
          widget.autoFetchCategoryId!,
          widget.autoFetchCategoryLabel ?? widget.autoFetchCategoryId!,
        );
      });
    }
  }

  Future<void> _fetchNearbyForCategory(String categoryId, String label) async {
    final ctx = widget.placeContext;
    if (ctx == null) return;
    final lat = ctx['latitude'];
    final lng = ctx['longitude'];
    if (lat is! num || lng is! num) return;

    final anchorName = (ctx['name'] as String?) ?? 'this place';

    setState(() {
      _activeCategoryChip = categoryId;
      _isFetchingPlaces = true;
      _showSuggestions = false;
      _messages.add(
        _ChatMessage(
          text: 'Show me $label near $anchorName',
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    try {
      final results = await GooglePlacesService.fetchNearbyPlaces(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        categoryName: categoryId,
        radius: 2000,
      );

      final top = results.take(6).toList();
      final intro = top.isEmpty
          ? "I couldn't find any $label spots within 2km of $anchorName right now."
          : 'Here are the closest $label spots near $anchorName:';

      if (mounted) {
        setState(() {
          _isFetchingPlaces = false;
          _messages.add(
            _ChatMessage(
              text: intro,
              isUser: false,
              timestamp: DateTime.now(),
              places: top.isEmpty ? null : top,
              placesCategoryLabel: label,
            ),
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Nearby fetch error: $e');
      if (mounted) {
        setState(() {
          _isFetchingPlaces = false;
          _messages.add(
            _ChatMessage(
              text:
                  "I had trouble pulling $label spots near $anchorName. Try again in a moment.",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    }
  }

  /// Resolves the user's current area + coordinates so Neva can tailor answers
  /// to where they actually are (e.g. "a day out with my gf" → ideas in their
  /// city). Best-effort: if location is unavailable she just answers generally.
  Future<void> _resolveUserLocation() async {
    if (_locationResolved) return;

    // If this chat was opened for a specific place (AR flow), anchor to it.
    final ctx = widget.placeContext;
    if (ctx != null && ctx['latitude'] is num && ctx['longitude'] is num) {
      _userLat = (ctx['latitude'] as num).toDouble();
      _userLng = (ctx['longitude'] as num).toDouble();
      final ctxName = (ctx['name'] as String?)?.trim();
      _userArea = (ctxName != null && ctxName.isNotEmpty)
          ? ctxName
          : await GooglePlacesService.reverseGeocode(_userLat!, _userLng!);
      _locationResolved = true;
      return;
    }

    try {
      final pos = await PermissionService.getSafePosition();
      if (pos == null) return; // not granted / unavailable — retry on next send
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      _userArea = await GooglePlacesService.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      _locationResolved = true;
    } catch (e) {
      debugPrint('Neva location resolve failed: $e');
    }
  }

  /// Location hint passed to Gemini so answers are grounded to the user's area.
  String? _locationContext() {
    final parts = <String>[];
    if (_userArea != null && _userArea!.isNotEmpty && _userArea != 'Nearby') {
      parts.add('The user is currently in/near $_userArea.');
    }
    if (_userLat != null && _userLng != null) {
      parts.add(
        'Their coordinates are ${_userLat!.toStringAsFixed(5)}, ${_userLng!.toStringAsFixed(5)}.',
      );
    }
    if (parts.isEmpty) return null;
    parts.add(
      'Tailor your suggestions to this area and mention it naturally. Do not ask the user where they are.',
    );
    return parts.join(' ');
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(
        _ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _showSuggestions = false;
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    // Make sure Neva knows where the user is so the answer is local.
    if (!_locationResolved) await _resolveUserLocation();

    try {
      final response = await _geminiService.getResponse(
        text,
        systemInstruction: _nevaSystemPrompt,
        context: _locationContext(),
        temperature: 0.85,
      );

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(
            _ChatMessage(
              text: response,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Gemini Chat Error: $e');
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(
            _ChatMessage(
              text:
                  "I'm having a bit of trouble connecting to my central processing ($e). Please check if the Gemini API key is active!",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.03),
                    ),
                  ),
                ),
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isTyping) {
                      return _buildTypingIndicator();
                    }
                    return _buildMessageBubble(_messages[index], index);
                  },
                ),
              ],
            ),
          ),
          // Integrated Suggestions and Input Area
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasPlaceContext) ...[
                  const SizedBox(height: 12),
                  _buildQuickActions(),
                  const SizedBox(height: 12),
                  _buildNearbyChips(),
                ],
                if (_showSuggestions) ...[
                  const SizedBox(height: 12),
                  _buildQuickSuggestions(),
                ],
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    bottomInset > 0
                        ? 12
                        : (bottomPadding > 0
                              ? bottomPadding + 8
                              : 16), // Clean safe-area responsive padding instead of a hardcoded 110px gap
                  ),
                  child: _buildInputBar(),
                ),
                SizedBox(height: bottomInset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNevaAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64B5F6).withValues(alpha: 0.5),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset(
          'assets/images/neva_avatar.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFF1976D2),
            child: const Center(
              child: Icon(Icons.face_5_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.05),
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: Icon(
        Icons.person_rounded,
        color: Colors.black26,
        size: size * 0.6,
      ),
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        topPadding > 0 ? topPadding + 10 : 24,
        24,
        16,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(
          bottom: BorderSide(color: Colors.black12, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (Navigator.canPop(context)) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.05),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.black87,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          _buildNevaAvatar(48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEVA',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'SPATIAL COGNITION PARTNER',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.black54,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message, int index) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Column(
              children: [
                _buildNevaAvatar(32),
                const SizedBox(height: 4),
                const Text(
                  'NEVA',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.black26,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                    border: !isUser
                        ? Border.all(color: Colors.black.withValues(alpha: 0.03))
                        : null,
                  ),
                  child: isUser
                      ? Text(
                          message.text,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.5,
                          ),
                        )
                      : _NevaFormattedText(
                          message.text,
                          baseStyle: const TextStyle(
                            fontSize: 15,
                            color: Colors.black87,
                            height: 1.5,
                          ),
                        ),
                ),
                if (message.places != null && message.places!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildPlacesList(message.places!),
                ],
              ],
            ),
          ),
          if (isUser) ...[const SizedBox(width: 10), _buildUserAvatar(32)],
        ],
      ),
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }

  Widget _buildTypingIndicator() {
    return Row(
      children: [
        _buildNevaAvatar(32),
        const SizedBox(width: 8),
        Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black.withValues(alpha: 0.04),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              return Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: const BoxDecoration(
                       shape: BoxShape.circle,
                      color: Colors.black26,
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    end: const Offset(1.5, 1.5),
                    delay: (i * 200).ms,
                    duration: 600.ms,
                  );
            }),
          ),
        ),
      ],
    ).animate().fade();
  }

  Widget _buildPlacesList(List<AttractionEntity> places) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: places.map((p) {
        final distM = p.distanceM;
        final distLabel = distM == null
            ? ''
            : (distM < 1000
                  ? '${distM.round()} m'
                  : '${(distM / 1000).toStringAsFixed(1)} km');

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SmartTourismMapPage(
                  initialLat: p.latitude,
                  initialLng: p.longitude,
                  destinationName: p.name,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: Colors.black.withValues(alpha: 0.05),
                    child: p.photoUrls.isNotEmpty
                        ? Image.network(
                            p.photoUrls.first,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.place_rounded,
                              color: Colors.black38,
                              size: 22,
                            ),
                          )
                        : const Icon(
                            Icons.place_rounded,
                            color: Colors.black38,
                            size: 22,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            p.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (distLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.straighten_rounded,
                              color: Colors.black38,
                              size: 11,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              distLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickActions() {
    final ctx = widget.placeContext;
    if (ctx == null) return const SizedBox.shrink();

    final name = ctx['name'] ?? 'Unknown Place';
    final lat = ctx['latitude'];
    final lng = ctx['longitude'];

    final mapsUrl = (lat != null && lng != null)
        ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
        : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}';

    final double finalLat = (lat as num?)?.toDouble() ?? _userLat ?? 6.9271;
    final double finalLng = (lng as num?)?.toDouble() ?? _userLng ?? 79.8612;

    final uberUri = Uri.https('m.uber.com', '/ul/', {
      'action': 'setPickup',
      'pickup': 'my_location',
      'dropoff[latitude]': finalLat.toStringAsFixed(6),
      'dropoff[longitude]': finalLng.toStringAsFixed(6),
      'dropoff[nickname]': name,
    });

    final bookingUri = Uri.https('www.booking.com', '/searchresults.html', {
      'ss': name.trim(),
      'latitude': finalLat.toStringAsFixed(6),
      'longitude': finalLng.toStringAsFixed(6),
    });

    Widget circleActionButton({
      Widget? child,
      IconData? icon,
      String? imagePath,
      required Color color,
      required int index,
      required VoidCallback onTap,
      bool fillImage = false,
    }) {
      return GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child:
                    child ??
                    (imagePath != null
                        ? (fillImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.asset(
                                    imagePath,
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: ClipOval(
                                    child: Image.asset(
                                      imagePath,
                                      fit: BoxFit.cover,
                                      width: 34,
                                      height: 34,
                                    ),
                                  ),
                                ))
                        : Icon(icon, color: Colors.white, size: 24)),
              ),
            ),
          )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .moveY(
            begin: -2,
            end: 2,
            duration: (1400 + (index * 200)).ms,
            curve: Curves.easeInOut,
          );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          circleActionButton(
            icon: Icons.explore_rounded,
            color: const Color(0xFF00C6FF),
            index: 0,
            onTap: () async {
              if (lat != null && lng != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmartTourismMapPage(
                      initialLat: lat.toDouble(),
                      initialLng: lng.toDouble(),
                      destinationName: name,
                    ),
                  ),
                );
              } else {
                try {
                  await launchUrl(
                    Uri.parse(mapsUrl),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {}
              }
            },
          ),
          const SizedBox(width: 16),
          circleActionButton(
            imagePath: 'assets/images/uber_logo.png',
            color: Colors.black,
            index: 1,
            onTap: () async {
              try {
                await launchUrl(uberUri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
          const SizedBox(width: 16),
          circleActionButton(
            imagePath: 'assets/images/booking_logo.jpg',
            color: Colors.white,
            index: 2,
            onTap: () async {
              try {
                await launchUrl(
                  bookingUri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}
            },
          ),
          const SizedBox(width: 16),
          circleActionButton(
            imagePath: 'assets/images/headout.png',
            color: Colors.transparent,
            index: 3,
            fillImage: true,
            onTap: () async {
              final headoutUri = await GooglePlacesService.getHeadoutSearchUri(finalLat, finalLng, name);
              try {
                await launchUrl(
                  headoutUri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyChips() {
    final placeName = (widget.placeContext?['name'] as String?) ?? 'here';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'NEAR $placeName'.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.black54,
              letterSpacing: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _nearbyCategories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = _nearbyCategories[index];
              final id = cat['id'] as String;
              final label = cat['label'] as String;
              final icon = cat['icon'] as IconData;
              final isActive = _activeCategoryChip == id && _isFetchingPlaces;

              return GestureDetector(
                onTap: _isFetchingPlaces
                    ? null
                    : () => _fetchNearbyForCategory(id, label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(icon, color: Colors.white, size: 13),
                      const SizedBox(width: 8),
                      Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickSuggestions() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        scrollDirection: Axis.horizontal,
        itemCount: _quickPrompts.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _sendMessage(_quickPrompts[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.black,
              ),
              child: Center(
                child: Text(
                  _quickPrompts[index].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Talk to Neva...',
                    hintStyle: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendMessage,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasText ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
                  boxShadow: hasText
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: hasText ? () => _sendMessage(_controller.text) : null,
                    customBorder: const CircleBorder(),
                    child: Center(
                      child: AnimatedScale(
                        scale: hasText ? 1.0 : 0.88,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: hasText ? Colors.white : const Color(0xFF9CA3AF),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<AttractionEntity>? places;
  final String? placesCategoryLabel;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.places,
    this.placesCategoryLabel,
  });
}

/// Renders Neva's replies with light Markdown so the chat looks polished
/// instead of showing raw `**` / `*` characters. Supports **bold**, *italic*,
/// `code`, bullet lists ("* ", "- ", "• "), numbered lists ("1. ") and strips
/// stray "#" headings — exactly the formatting Neva is prompted to produce.
class _NevaFormattedText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const _NevaFormattedText(this.text, {required this.baseStyle});

  // Inline emphasis, longest markers first so **bold** wins over *italic*.
  static final RegExp _inlineRe = RegExp(
    r'(\*\*([^*]+)\*\*)|(__([^_]+)__)|(\*([^*]+)\*)|(`([^`]+)`)',
  );

  List<InlineSpan> _inline(String content) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _inlineRe.allMatches(content)) {
      if (m.start > i) {
        spans.add(TextSpan(text: content.substring(i, m.start)));
      }
      if (m.group(2) != null || m.group(4) != null) {
        spans.add(
          TextSpan(
            text: m.group(2) ?? m.group(4),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (m.group(6) != null) {
        spans.add(
          TextSpan(
            text: m.group(6),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(8),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: (baseStyle.fontSize ?? 15) - 1,
            ),
          ),
        );
      }
      i = m.end;
    }
    if (i < content.length) spans.add(TextSpan(text: content.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.replaceAll('\r\n', '\n').trim().split('\n');
    final bulletRe = RegExp(r'^\s*[-*•]\s+(.*)$');
    final numberRe = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
    final headingRe = RegExp(r'^\s*#{1,6}\s+(.*)$');
    final children = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        continue;
      }

      final heading = headingRe.firstMatch(line);
      if (heading != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text.rich(
              TextSpan(
                style: baseStyle.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: (baseStyle.fontSize ?? 15) + 1,
                ),
                children: _inline(heading.group(1)!),
              ),
            ),
          ),
        );
        continue;
      }

      final bullet = bulletRe.firstMatch(line);
      if (bullet != null) {
        children.add(
          _row(
            marker: '•',
            markerStyle: baseStyle.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
            content: bullet.group(1)!,
          ),
        );
        continue;
      }

      final number = numberRe.firstMatch(line);
      if (number != null) {
        children.add(
          _row(
            marker: '${number.group(1)}.',
            markerStyle: baseStyle.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
            content: number.group(2)!,
          ),
        );
        continue;
      }

      children.add(
        Text.rich(TextSpan(style: baseStyle, children: _inline(line))),
      );
    }

    if (children.isEmpty) children.add(Text(text, style: baseStyle));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _row({
    required String marker,
    required TextStyle markerStyle,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, left: 2, right: 8),
            child: Text(marker, style: markerStyle),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(style: baseStyle, children: _inline(content)),
            ),
          ),
        ],
      ),
    );
  }
}
