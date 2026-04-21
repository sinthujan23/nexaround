import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AiChatPage extends StatefulWidget {
  final String? initialPrompt;
  const AiChatPage({super.key, this.initialPrompt});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _showSuggestions = true;

  final List<String> _quickPrompts = [
    '🌙 Safe night spots',
    '🍜 Authentic hoppers',
    '🏛 Hidden history',
    '💸 Local prices',
  ];

  final Map<String, String> _mockResponses = {
    'lotus': "The Lotus Temple is an architectural masterpiece. It was designed to symbolize purity and peace. Currently, it's one of the most visited spots in the city for both tourists and spiritual practitioners.",
    'museum': "The Colombo Museum is the oldest public museum in the country. It houses some of the most precious royal artifacts from the Kandyan era. I recommend seeing the royal throne!",
    'food': "Ah, the Street Food Corner! You'll find the best hoppers in the city here. Make sure to try them with the 'pol sambol' for a real authentic kick.",
    'night': "Colombo comes alive at night. If you're near Galle Face, the street food there is legendary, but for a more 'hidden' vibe, I'd suggest the lounge at the Dutch Hospital. Totally safe and very chill.",
    'history': "Most people miss the colonial tunnels beneath the fort area. They aren't officially open, but walk by the old lighthouse and you'll feel the history breathing through the stone.",
    'market': "The Craft Market is where traditional artisans from all over the island come to sell. It's the best place for unique, hand-carved souvenirs.",
    'default': "I'm looking into that for you. Based on your current mood and the local vibe, I'd say you're about to discover something amazing. What else is on your mind?",
  };

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      text: "Hey Alex! I'm Neva. I'm not just your guide—I'm your eyes and ears on the ground. \n\nWhere are we exploring today? I've got some secret spots pinned for you.",
      isUser: false,
      timestamp: DateTime.now(),
    ));

    if (widget.initialPrompt != null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _sendMessage(widget.initialPrompt!);
      });
    }
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true, timestamp: DateTime.now()));
      _showSuggestions = false;
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    final key = text.toLowerCase();
    String response = _mockResponses['default']!;
    for (final entry in _mockResponses.entries) {
      if (key.contains(entry.key)) {
        response = entry.value;
        break;
      }
    }

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(text: response, isUser: false, timestamp: DateTime.now()));
        });
        _scrollToBottom();
      }
    });
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
                if (_showSuggestions) ...[
                  const SizedBox(height: 12),
                  _buildQuickSuggestions(),
                ],
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 110),
                  child: _buildInputBar(),
                ),
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Row(
        children: [
          _buildNevaAvatar(56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEVA',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 2),
                ),
                Text(
                  'SPATIAL COGNITION PARTNER',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54, letterSpacing: 1),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
            child: const Icon(Icons.emergency_rounded, color: Colors.black),
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
            child: Container(
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

  _ChatMessage({required this.text, required this.isUser, required this.timestamp});
}
