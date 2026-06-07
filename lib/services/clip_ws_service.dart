import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart' as config;

// ── Clip WebSocket Service ────────────────────────────────────
// Manages the persistent WebSocket connection to API Gateway.
//
// Two roles share this service:
//   • Scorer device  — calls sendClipTrigger() after a wicket/boundary
//   • Camera device  — listens to onTrigger stream to start clip recording
//
// Single-device mode (scoring + camera on the same phone):
//   The Lambda filters out the sender's own connection, so WebSocket
//   triggers never loop back. We solve this with a local broadcast stream
//   (_localTrigger) that sendClipTrigger() always fires — the camera
//   screen receives it instantly without going through the network.
//
// Usage:
//   await ClipWsService.instance.connect(matchId);
//   ClipWsService.instance.onTrigger.listen((t) { /* record clip */ });
//   ClipWsService.instance.sendClipTrigger(...);
//   ClipWsService.instance.disconnect();

const _wsUrl = config.wsUrl;

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

  // Remote triggers — received from other devices via WebSocket
  final _triggerCtrl = StreamController<ClipTriggerEvent>.broadcast();

  // Local triggers — fired immediately when THIS device scores an event.
  static final _localTrigger = StreamController<ClipTriggerEvent>.broadcast();

  /// Combined stream: receives triggers from both WebSocket (other devices)
  /// and local events (same device). Camera screen subscribes to this.
  Stream<ClipTriggerEvent> get onTrigger =>
      StreamGroup.merge([_triggerCtrl.stream, _localTrigger.stream]);

  bool get isConnected => _channel != null;

  // ── Buffering state — shared between CameraBufferScreen and ScoringScreen ──
  bool _isBuffering = false;
  bool get isBuffering => _isBuffering;

  final _bufferingCtrl = StreamController<bool>.broadcast();
  Stream<bool> get onBufferingChanged => _bufferingCtrl.stream;

  void setBuffering(bool active) {
    _isBuffering = active;
    _bufferingCtrl.add(active);
  }

  Future<void> connect(String matchId) async {
    if (_channel != null && _matchId == matchId) return; // already connected
    await _disconnectChannel(); // disconnect WS only, preserve buffering state
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
  /// Also fires locally so the camera works when running on the same device.
  void sendClipTrigger({
    required String matchId,
    required int inningsNumber,
    required int over,
    required int ball,
    required String event, // 'wicket' | 'four' | 'six'
  }) {
    final trigger = ClipTriggerEvent(
      matchId: matchId,
      inningsNumber: inningsNumber,
      over: over,
      ball: ball,
      event: event,
      ts: DateTime.now().millisecondsSinceEpoch,
    );

    // Always fire locally — camera screen on same device gets it immediately
    _localTrigger.add(trigger);

    // Also send via WebSocket for camera devices on other phones
    _channel?.sink.add(jsonEncode({
      'action': 'clipTrigger',
      'matchId': matchId,
      'inningsNumber': inningsNumber,
      'over': over,
      'ball': ball,
      'event': event,
    }));
  }

  // Internal: close the WS channel without touching buffering state
  Future<void> _disconnectChannel() async {
    _matchId = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  // Full disconnect — also clears buffering state
  Future<void> disconnect() async {
    await _disconnectChannel();
    setBuffering(false);
  }

  void dispose() {
    disconnect();
    _triggerCtrl.close();
    _bufferingCtrl.close();
  }
}

// ── StreamGroup helper ────────────────────────────────────────
// Merges multiple streams into one without a package dependency.
class StreamGroup {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    final ctrl = StreamController<T>.broadcast();
    for (final s in streams) {
      s.listen(ctrl.add, onError: ctrl.addError);
    }
    return ctrl.stream;
  }
}
