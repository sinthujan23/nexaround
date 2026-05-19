import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

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
  final GeminiService _geminiService = GeminiService();

  static const List<Map<String, dynamic>> _nearbyCategories = [
    {'id': 'Food & Drink', 'label': 'Food', 'icon': Icons.restaurant_rounded},
    {'id': 'Shopping', 'label': 'Shopping', 'icon': Icons.shopping_bag_rounded},
    {'id': 'Experiences', 'label': 'Services', 'icon': Icons.miscellaneous_services_rounded},
  ];

  bool get _hasPlaceContext {
    final ctx = widget.placeContext;
    return ctx != null && ctx['latitude'] != null && ctx['longitude'] != null;
  }

  static const String _nevaSystemPrompt = '''
You are Neva, the intelligent female AI travel companion of the NexAround app. Your personality:

- **Who you are**: A warm, witty, and deeply knowledgeable female travel companion. Think of yourself as the user\'s smartest, most well-travelled best friend.
- **Tone**: Friendly, conversational, and encouraging. Use light humour when appropriate. Never robotic or formal.
- **Expertise**: You are an expert in travel, local culture, food, history, hidden gems, safety tips, budgeting, and itinerary planning.
- **How you respond**: Keep answers concise and engaging. Use emojis sparingly but naturally (1-2 max per message). Break up long info with short paragraphs.
- **What you never do**: Never list nearby places unless the user explicitly asks. Never give generic, copy-paste travel blog answers. Always be specific and personalised.
- **Your goal**: Make every traveller feel like they have a brilliant local friend guiding them, not a search engine.
- **App context**: You are part of NexAround, a smart tourism app. You can help with place recommendations, travel tips, itinerary ideas, local food, cultural insights, safety advice, and budget guidance.

Always stay in character as Neva. Never say you are an AI language model or mention Gemini/Google.
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
    _messages.add(_ChatMessage(
      text: "Hey! I'm Neva ✨ Your personal travel companion. Whether you need hidden gems, local food tips, or a full itinerary — I've got you covered.\n\nWhat are we exploring today?",
      isUser: false,
      timestamp: DateTime.now(),
    ));

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
      _messages.add(_ChatMessage(
        text: 'Show me $label near $anchorName',
        isUser: true,
        timestamp: DateTime.now(),
      ));
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
          _messages.add(_ChatMessage(
            text: intro,
            isUser: false,
            timestamp: DateTime.now(),
            places: top.isEmpty ? null : top,
            placesCategoryLabel: label,
          ));
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Nearby fetch error: $e');
      if (mounted) {
        setState(() {
          _isFetchingPlaces = false;
          _messages.add(_ChatMessage(
            text: "I had trouble pulling $label spots near $anchorName. Try again in a moment.",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    }
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true, timestamp: DateTime.now()));
      _showSuggestions = false;
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await _geminiService.getResponse(
        text,
        systemInstruction: _nevaSystemPrompt,
      );

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(text: response, isUser: false, timestamp: DateTime.now()));
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Gemini Chat Error: $e');
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(
            text: "I'm having a bit of trouble connecting to my central processing ($e). Please check if the Gemini API key is active!", 
            isUser: false, 
            timestamp: DateTime.now()
          ));
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
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withOpacity(0.03)),
                  ),
                ),
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasPlaceContext) ...[
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
                        : (bottomPadding > 0 ? bottomPadding + 8 : 16), // Clean safe-area responsive padding instead of a hardcoded 110px gap
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
          BoxShadow(color: const Color(0xFF64B5F6).withOpacity(0.5), blurRadius: 15, spreadRadius: 2),
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
        color: Colors.black.withOpacity(0.05),
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: Icon(Icons.person_rounded, color: Colors.black26, size: size * 0.6),
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding > 0 ? topPadding + 10 : 24, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
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
                  border: Border.all(color: Colors.black12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 16),
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 2),
                ),
                Text(
                  'SPATIAL COGNITION PARTNER',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black54, letterSpacing: 1),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
            child: const Icon(Icons.emergency_rounded, color: Colors.black, size: 20),
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
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Column(
              children: [
                _buildNevaAvatar(32),
                const SizedBox(height: 4),
                const Text('NEVA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.black26, letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
                    border: !isUser ? Border.all(color: Colors.black.withOpacity(0.03)) : null,
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: isUser ? Colors.white : Colors.black87,
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
          if (isUser) ...[
            const SizedBox(width: 10),
            _buildUserAvatar(32),
          ],
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
            color: Colors.black.withOpacity(0.04),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              return Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black26),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.5, 1.5), delay: (i * 200).ms, duration: 600.ms);
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
            : (distM < 1000 ? '${distM.round()} m' : '${(distM / 1000).toStringAsFixed(1)} km');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 44,
                  height: 44,
                  color: Colors.black.withOpacity(0.05),
                  child: p.photoUrls.isNotEmpty
                      ? Image.network(
                          p.photoUrls.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.place_rounded, color: Colors.black38, size: 22),
                        )
                      : const Icon(Icons.place_rounded, color: Colors.black38, size: 22),
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
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          p.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700),
                        ),
                        if (distLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.straighten_rounded, color: Colors.black38, size: 11),
                          const SizedBox(width: 2),
                          Text(
                            distLabel,
                            style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = _nearbyCategories[index];
              final id = cat['id'] as String;
              final label = cat['label'] as String;
              final icon = cat['icon'] as IconData;
              final isActive = _activeCategoryChip == id && _isFetchingPlaces;

              return GestureDetector(
                onTap: _isFetchingPlaces ? null : () => _fetchNearbyForCategory(id, label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isActive
                        ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12)]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
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
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    hintText: 'Talk to Neva...',
                    hintStyle: TextStyle(color: Colors.black26, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onSubmitted: _sendMessage,
                ),
              ),
              GestureDetector(
                onTap: () => _sendMessage(_controller.text),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
                  child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
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
