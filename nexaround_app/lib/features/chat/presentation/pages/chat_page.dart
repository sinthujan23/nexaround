import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/chat/domain/entities/chat_message.dart';
import 'package:nexaround_app/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:nexaround_app/features/chat/presentation/bloc/chat_event.dart';
import 'package:nexaround_app/features/chat/presentation/bloc/chat_state.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  void _sendMessage([String? text]) {
    final message = text ?? _messageController.text;
    if (message.trim().isNotEmpty) {
      context.read<ChatBloc>().add(SendChatMessage(message.trim()));
      _messageController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildArchitecturalAppBar(context),
      body: Stack(
        children: [
          // Elegant Background Accents
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.03),
              ),
            ).animate().blur(begin: const Offset(80, 80), end: const Offset(100, 100)),
          ),
          
          Column(
            children: [
              Expanded(
                child: BlocConsumer<ChatBloc, ChatState>(
                  listener: (context, state) {
                    if (state.status == ChatStatus.success || state.status == ChatStatus.loading) {
                      _scrollToBottom();
                    }
                  },
                  builder: (context, state) {
                    if (state.messages.isEmpty) {
                      return _buildEmptyState();
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 140, 24, 40),
                      itemCount: state.messages.length + (state.status == ChatStatus.loading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == state.messages.length) {
                          return _buildNeuralTypingIndicator()
                              .animate().fade().slideY(begin: 0.1, end: 0);
                        }
                        return _ChatBubble(message: state.messages[index])
                            .animate().fade().slideY(begin: 0.1, end: 0);
                      },
                    );
                  },
                ),
              ),
              _buildFloatingCommandSurface(),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildArchitecturalAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(100),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            toolbarHeight: 100,
            backgroundColor: AppColors.background.withOpacity(0.8),
            elevation: 0,
            centerTitle: true,
            leading: Center(
              child: Container(
                margin: const EdgeInsets.only(left: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const IconButton(
                  icon: Icon(Icons.auto_awesome_rounded, color: AppColors.secondary, size: 20),
                  onPressed: null,
                ),
              ),
            ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 3.seconds, color: Colors.white24),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NEURAL GUIDE',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    ).animate(onPlay: (c) => c.repeat()).fade(begin: 0.2, end: 1, duration: 1.seconds),
                    const SizedBox(width: 6),
                    Text(
                      'AI OPERATIONAL',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary, size: 22),
                onPressed: () => context.read<ChatBloc>().add(ClearChatHistory()),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.auto_awesome, size: 40, color: AppColors.primary),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(begin: const Offset(0.9, 0.9), delay: 500.ms, duration: 2.seconds),
            const SizedBox(height: 32),
            const Text(
              'A world of discovery awaits',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ).animate().fade().slideY(begin: 0.2, end: 0),
            const SizedBox(height: 12),
            Text(
              'Your personal AI guide is ready to curate\nyour next local masterpiece.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6),
            ).animate().fade(delay: 200.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 48),
            _buildActionChip('Discover curated hidden gems nearby'),
            const SizedBox(height: 12),
            _buildActionChip('Tell me the story of this city'),
            const SizedBox(height: 12),
            _buildActionChip('Plan a minimalist itinerary'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip(String text) {
    return GestureDetector(
      onTap: () => _sendMessage(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    ).animate().fade(delay: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNeuralTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceVariant,
            child: const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Curating response...',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 1.seconds),
        ],
      ),
    );
  }

  Widget _buildFloatingCommandSurface() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ask the Neural Guide...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _sendMessage(),
            child: Container(
              height: 54,
              width: 54,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.north_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ).animate().slideY(begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutBack),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == MessageSender.user;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceVariant,
              child: const Icon(Icons.auto_awesome, size: 12, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: Radius.circular(isUser ? 24 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 24),
                ),
                border: isUser ? null : Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? Colors.white : AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}
