import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChannelManager {
  static WebSocketChannel? channel;
  static Stream<dynamic>? broadcastStream;
}