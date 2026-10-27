import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'config.dart';

class SocketService {
  SocketService._internal();
  static final SocketService instance = SocketService._internal();

  io.Socket? _socket;
  final _usersController = StreamController<List<dynamic>>.broadcast();
  final _historyController = StreamController<List<dynamic>>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _readController = StreamController<Map<String, dynamic>>.broadcast();
  final _deletedController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<List<dynamic>> get users => _usersController.stream;
  Stream<List<dynamic>> get history => _historyController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get typing => _typingController.stream;
  Stream<Map<String, dynamic>> get messagesRead => _readController.stream;
  Stream<Map<String, dynamic>> get messageDeleted => _deletedController.stream;
  Stream<bool> get isConnected => _connectionController.stream;

  bool get connected => _socket?.connected ?? false;

  void connect(String token) {
    disconnect();

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionAttempts(10)
          .setQuery({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      _connectionController.add(true);
      refreshUsers();
    });

    _socket!.onDisconnect((_) {
      _connectionController.add(false);
    });

    _socket!.on('user_list', (data) {
      if (data is List) {
        _usersController.add(data);
      }
    });

    _socket!.on('message_history', (data) {
      if (data is List) {
        _historyController.add(data);
      }
    });

    _socket!.on('new_message', (data) {
      if (data != null) {
        _messageController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('typing_status', (data) {
      if (data != null) {
        _typingController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('messages_read', (data) {
      if (data != null) {
        _readController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('message_deleted', (data) {
      if (data != null) {
        _deletedController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.connect();
  }

  void refreshUsers() {
    _socket?.emit('get_users');
  }

  void loadHistory(int userId) {
    _socket?.emit('get_history', {'user_id': userId});
  }

  void sendMessage(int to, String text, {String? clientId}) {
    _socket?.emit('send_message', {
      'to': to,
      'message': text,
      'client_id': clientId,
    });
  }

  void markAsRead(int senderId) {
    _socket?.emit('mark_read', {'sender_id': senderId});
  }

  void sendTyping(int to, bool isTyping) {
    _socket?.emit('typing', {'to': to, 'is_typing': isTyping});
  }

  void deleteMessage(int messageId) {
    _socket?.emit('delete_message', {'message_id': messageId});
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connectionController.add(false);
  }
}