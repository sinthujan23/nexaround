import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/chat/data/repositories/chat_repository.dart';
import 'package:nexaround_app/features/chat/domain/entities/chat_message.dart';
import 'package:nexaround_app/features/chat/presentation/bloc/chat_event.dart';
import 'package:nexaround_app/features/chat/presentation/bloc/chat_state.dart';
import 'package:uuid/uuid.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _repository;
  final _uuid = const Uuid();

  ChatBloc(this._repository) : super(const ChatState()) {
    on<SendChatMessage>(_onSendChatMessage);
    on<ClearChatHistory>(_onClearChatHistory);
  }

  Future<void> _onSendChatMessage(
    SendChatMessage event,
    Emitter<ChatState> emit,
  ) async {
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      text: event.message,
      sender: MessageSender.user,
      timestamp: DateTime.now(),
    );

    final updatedMessages = List<ChatMessage>.from(state.messages)..add(userMessage);
    emit(state.copyWith(
      status: ChatStatus.loading,
      messages: updatedMessages,
    ));

    try {
      final aiResponseText = await _repository.sendMessage(
        event.message,
        context: event.context,
      );

      final aiMessage = ChatMessage(
        id: _uuid.v4(),
        text: aiResponseText,
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
      );

      emit(state.copyWith(
        status: ChatStatus.success,
        messages: List<ChatMessage>.from(state.messages)..add(aiMessage),
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onClearChatHistory(ClearChatHistory event, Emitter<ChatState> emit) {
    emit(const ChatState());
  }
}
