import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/chat/domain/entities/chat_message.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

class SendChatMessage extends ChatEvent {
  final String message;
  final String? context;
  const SendChatMessage(this.message, {this.context});

  @override
  List<Object?> get props => [message, context];
}

class ClearChatHistory extends ChatEvent {}
