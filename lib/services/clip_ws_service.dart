import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

// ── Clip WebSocket Service ────────────────────────────────────
// Manages the persistent WebSocket connection to API Gateway.
//
// Two roles share this service:
//   • Scorer device  — calls sendClipTrigger() after a wicket/boundary
//   • Camera device  — listens to onTrigger stream to start clip recording
//
// Usage:
//   await ClipWsService.instance.connect(matchId);
//   ClipWsService.instance.onTrigger.listen((t) { /* record clip */ });
//   ClipWsService.instance.sendClipTrigger(...);
//   ClipWsService.instance.disconnect();

// IMPORTANT: replace this URL after creating the API Gateway WebSocket API.
const _wsUrl = 'wss://2fziydn0oj.execute-api.us-east-1.amazonaws.com/dev';

class ClipTriggerEvent {
  final String matchId;
  final int inningsNumber, over, ball;
  final String event; // 'wicket' | 'four' | 'six' | 'manual'
  final int ts;

  const ClipTriggerEvent({
    required this.matchId,
    required this.inningsNumber,
    required this.over,
    required this.ball,
    required this.event,
    required this.ts,
  });

  factory ClipTriggerEvent.fromJson(Map<String, dynamic> j) => ClipTriggerEvent(
    matchId:      j['matchId']       as String,
    inningsNumber:(j['inningsNumber'] as num?)?.toInt() ?? 1,
    over:         (j['over']          as num?)?.toInt() ?? 0,
    ball:         (j['ball']          as num?)?.toInt() ?? 0,
    event:         j['event']         as String? ?? 'manual',
    ts:           (j['ts']            as num?)?.toInt() ?? 0,
  );
}

class ClipWsService {
  ClipWsService._();
  static final instance = ClipWsService._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _matchId;

  final _triggerCtrl = StreamController<ClipTriggerEvent>.broadcast();
  Stream<ClipTriggerEvent> get onTrigger => _triggerCtrl.stream;

  bool get isConnected => _channel != null;

  Future<void> connect(String matchId) async {
    if (_channel != null && _matchId == matchId) return; // already connected
    await disconnect();
    _matchId = matchId;

    _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
    await _channel!.ready.catchError((_) {}); // non-fatal on older flutter_web_socket

    // Tell the server which match we're watching
    _channel!.sink.add(jsonEncode({'action': 'joinMatch', 'matchId': matchId}));

    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          if (msg['type'] == 'clipTrigger') {
            _triggerCtrl.add(ClipTriggerEvent.fromJson(msg));
          }
        } catch (_) {}
      },
      onDone: () {
        // Auto-reconnect after 3s if we didn't intentionally disconnect
        if (_matchId != null) {
          Future.delayed(const Duration(seconds: 3), () {
            if (_matchId != null) connect(_matchId!);
          });
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Send a clip trigger to all camera devices watching the same match.
  void sendClipTrigger({
    required String matchId,
    required int inningsNumber,
    required int over,
    required int ball,
    required String event, // 'wicket' | 'four' | 'six'
  }) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'action': 'clipTrigger',
      'matchId': matchId,
      'inningsNumber': inningsNumber,
      'over': over,
      'ball': ball,
      'event': event,
    }));
  }

  Future<void> disconnect() async {
    _matchId = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _triggerCtrl.close();
  }
}
