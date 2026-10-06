import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../repository/reading_room_repository.dart';

enum RoomSyncState { connecting, live, fallback, stopped }

/// Metadata-only room synchronizer. The event itself never contains a memo,
/// quote, comment, or highlight color; consumers refetch through REST so the
/// server remains the spoiler and membership policy authority.
class RoomSyncClient {
  RoomSyncClient({
    required this.repository,
    required this.baseUrl,
    required this.token,
    required this.roomId,
    required this.onChanged,
  });

  final ReadingRoomRepository repository;
  final String baseUrl;
  final String? token;
  final int roomId;
  final VoidCallback onChanged;
  final ValueNotifier<RoomSyncState> state = ValueNotifier(
    RoomSyncState.connecting,
  );
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _poll;
  int _lastEventId = 0;
  int _attempt = 0;
  bool _closed = false;

  void start() {
    if (token == null || token!.isEmpty) {
      _startFallback();
      return;
    }
    _connect();
  }

  void _connect() {
    if (_closed) return;
    state.value = RoomSyncState.connecting;
    final uri = Uri.parse(baseUrl).replace(
      scheme: Uri.parse(baseUrl).scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/reading-room-sync',
      queryParameters: {'roomId': '$roomId', 'token': token!},
    );
    try {
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _event,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _attempt = 0;
      state.value = RoomSyncState.live;
      _poll?.cancel();
      unawaited(_sync());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _event(dynamic value) {
    try {
      final json = jsonDecode(value as String) as Map<String, dynamic>;
      final id = (json['id'] as num?)?.toInt() ?? 0;
      if (id > _lastEventId) {
        _lastEventId = id;
        onChanged();
      }
    } catch (_) {
      unawaited(_sync());
    }
  }

  void _scheduleReconnect() {
    if (_closed || _retry != null) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_attempt >= 4) {
      _startFallback();
      return;
    }
    final seconds = 1 << _attempt++;
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      _connect();
    });
  }

  void _startFallback() {
    if (_closed) return;
    state.value = RoomSyncState.fallback;
    _poll ??= Timer.periodic(const Duration(seconds: 20), (_) => _sync());
    unawaited(_sync());
  }

  Future<void> _sync() async {
    if (_closed) return;
    try {
      final ids = await repository.syncEventIds(roomId, _lastEventId);
      if (ids.isNotEmpty) {
        _lastEventId = ids.last;
        onChanged();
      }
    } catch (_) {
      // The next scheduled retry/manual refresh remains available. Do not
      // surface transport details to a reader in the middle of a book.
    }
  }

  void dispose() {
    _closed = true;
    state.value = RoomSyncState.stopped;
    _retry?.cancel();
    _poll?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    state.dispose();
  }
}
