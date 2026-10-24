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

  Stream<List<dynamic>> get users => _usersController.stream;
  Stream<List<dynamic>> get history => _historyController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  void connect(String token) {
    disconnect();
    _socket = io.io('$serverUrl?token=$token',
        io.OptionBuilder().setTransports(['websocket']).build());
    _socket!.on('user_list', (data) => _usersController.add(data));
    _socket!.on('message_history', (data) => _historyController.add(data));
    _socket!.on('new_message',
        (data) => _messageController.add(Map<String, dynamic>.from(data)));
  }

  void sendMessage(int to, String text) =>
      _socket?.emit('send_message', {'to': to, 'message': text});

  void loadHistory(int userId) =>
      _socket?.emit('get_history', {'user_id': userId});

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
