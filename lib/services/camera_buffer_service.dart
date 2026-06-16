import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'clip_ws_service.dart';

// ── CameraBufferService ───────────────────────────────────────
// Singleton that owns the camera + buffering loop independently of
// any widget lifecycle. CameraBufferScreen is a thin observer.
//
// This allows the user to navigate away (back to scoring) while
// buffering continues in the background.
//
class CameraBufferService with WidgetsBindingObserver {
  CameraBufferService._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = CameraBufferService._();

  // ── Public state ──────────────────────────────────────────────
  CameraController? cam;
  bool   cameraReady   = false;
  bool   cameraError   = false; // true when init failed — show retry
  bool   buffering     = false;
  bool   capturing     = false;
  String status        = 'Ready';
  String matchId       = '';
  final  log           = <String>[];

  static const _segmentSecs  = 10;
  static const _maxSegments  = 2;
  static const _postRollSecs = 5;

  final _buffer         = Queue<File>();
  ClipTriggerEvent?    _pendingTrigger;
  StreamSubscription<ClipTriggerEvent>? _wsSub;
  bool _loopRunning     = false; // prevents concurrent buffer loops
  bool _initInProgress  = false; // prevents concurrent camera inits

  // Widgets subscribe to this to redraw when state changes.
  final _stateCtrl = StreamController<void>.broadcast();
  Stream<void> get onStateChanged => _stateCtrl.stream;

  void _notify() => _stateCtrl.add(null);

  // ── App lifecycle ─────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Truly backgrounded — release camera resources but keep buffering flag.
      if (cam != null && cam!.value.isInitialized) {
        if (cam!.value.isRecordingVideo) {
          cam!.stopVideoRecording().ignore();
        }
        cam!.dispose();
        cam = null;
        cameraReady = false;
        _loopRunning = false; // loop will exit on next iteration (cam==null guard)
        _notify();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Came back — reinit camera if needed.
      if (!cameraReady && !_initInProgress) {
        initCamera().then((_) {
          // Only restart loop if we were buffering and loop isn't already running.
          if (cameraReady && buffering && !_loopRunning) _runBufferLoop();
        });
      }
    }
  }

  // ── Camera init ───────────────────────────────────────────────
  Future<void> initCamera() async {
    if (cameraReady || _initInProgress) return;
    _initInProgress = true;
    cameraError = false;
    status = 'Initialising camera…';
    _notify();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        status = 'No camera found';
        cameraError = true;
        _notify();
        _initInProgress = false;
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // Dispose any stale controller before creating a new one.
      if (cam != null) {
        try { await cam!.dispose(); } catch (_) {}
        cam = null;
      }
      final ctrl = CameraController(back, ResolutionPreset.high, enableAudio: true);
      await ctrl.initialize();
      cam          = ctrl;
      cameraReady  = true;
      cameraError  = false;
      status       = 'Ready';
      _notify();
    } catch (e) {
      cameraError = true;
      status = 'Camera error — tap to retry';
      _notify();
    } finally {
      _initInProgress = false;
    }
  }

  // ── Start buffering ───────────────────────────────────────────
  Future<void> startBuffering(String id) async {
    if (buffering || cam == null || !cam!.value.isInitialized) return;
    matchId   = id;
    buffering = true;
    status    = '🔴 Buffering…';
    _buffer.clear();
    ClipWsService.instance.setBuffering(true);
    _notify();

    if (matchId.isNotEmpty) {
      await ClipWsService.instance.connect(matchId);
      _wsSub?.cancel();
      _wsSub = ClipWsService.instance.onTrigger.listen(_onTrigger);
    }

    _runBufferLoop();
  }

  Future<void> _runBufferLoop() async {
    if (_loopRunning) return; // ← key guard: only one loop at a time
    _loopRunning = true;

    while (buffering) {
      // Wait while capture is in progress.
      if (capturing) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      // Camera lost (e.g. screen lock) — wait for reinit.
      if (cam == null || !cam!.value.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      // Already recording somehow — wait.
      if (cam!.value.isRecordingVideo) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }
      try {
        await cam!.startVideoRecording();
        await Future.delayed(const Duration(seconds: _segmentSecs));

        // If a capture started mid-segment, let _captureAndUpload take over.
        if (!buffering || capturing) break;

        final xFile = await cam!.stopVideoRecording();
        final seg   = File(xFile.path);

        if (_buffer.length >= _maxSegments) {
          final old = _buffer.removeFirst();
          try { old.deleteSync(); } catch (_) {}
        }
        _buffer.addLast(seg);

        if (_pendingTrigger != null) {
          final t = _pendingTrigger!;
          _pendingTrigger = null;
          unawaited(_captureAndUpload(t));
        }
      } catch (e) {
        if (buffering) {
          status = 'Camera error: $e';
          _notify();
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    _loopRunning = false;
  }

  // ── Stop buffering ────────────────────────────────────────────
  void stopBuffering() {
    if (!buffering) return;
    buffering = false;
    status    = 'Stopped';
    ClipWsService.instance.setBuffering(false);
    _wsSub?.cancel();
    _wsSub = null;
    _notify();
  }

  // ── Trigger ───────────────────────────────────────────────────
  void _onTrigger(ClipTriggerEvent t) {
    if (capturing) { _pendingTrigger = t; return; }
    unawaited(_captureAndUpload(t));
  }

  // ── Capture + upload ──────────────────────────────────────────
  Future<void> _captureAndUpload(ClipTriggerEvent t) async {
    if (capturing || cam == null) return;
    capturing = true;
    status    = '🎬 Capturing post-roll…';
    _notify();

    final preSegments = _buffer.toList();
    if (cam!.value.isRecordingVideo) {
      try {
        final xFile = await cam!.stopVideoRecording();
        preSegments.add(File(xFile.path));
      } catch (_) {}
    }

    try {
      await cam!.startVideoRecording();
      await Future.delayed(const Duration(seconds: _postRollSecs));
      final postXFile = await cam!.stopVideoRecording();
      final postFile  = File(postXFile.path);

      final allSegments     = [...preSegments, postFile];
      final totalDurationMs = allSegments.length * _segmentSecs * 1000;

      status = '☁️ Uploading ${allSegments.length} segments…';
      _notify();

      final primaryIdx = allSegments.length >= 2 ? allSegments.length - 2 : 0;
      String? primaryS3Key;

      for (var i = 0; i < allSegments.length; i++) {
        final seg    = allSegments[i];
        final isPost = i == allSegments.length - 1;
        final segEvt = isPost ? '${t.event}_post' : '${t.event}_pre${i + 1}';

        final presign = await ClipApi.presign(
          matchId: t.matchId, inningsNumber: t.inningsNumber,
          over: t.over, ball: t.ball, event: segEvt,
        );

        final bytes = await seg.readAsBytes();
        final res   = await http.put(
          Uri.parse(presign.uploadUrl),
          headers: {'Content-Type': 'video/mp4'},
          body: bytes,
        );
        if (res.statusCode != 200) throw Exception('S3 upload $i failed: ${res.statusCode}');
        if (i == primaryIdx) primaryS3Key = presign.s3Key;
      }

      if (primaryS3Key != null) {
        await ClipApi.save(
          matchId: t.matchId, inningsNumber: t.inningsNumber,
          over: t.over, ball: t.ball, event: t.event,
          s3Key: primaryS3Key, durationMs: totalDurationMs,
        );
      }

      for (final f in preSegments) {
        try { f.deleteSync(); } catch (_) {}
      }
      // Seed the buffer with the post-roll so the next event has immediate pre-roll.
      _buffer.clear();
      _buffer.addLast(postFile);

      final label = '${t.eventEmoji} ${t.event} @ ${t.over}.${t.ball + 1} — ${allSegments.length} segs';
      capturing    = false;
      status       = '✅ Uploaded';
      log.insert(0, label);
      _notify();

    } catch (e) {
      capturing = false;
      status    = '❌ Upload failed: $e';
      _notify();
    } finally {
      // Resume loop — only if not already running (guard prevents double-start).
      if (buffering && !_loopRunning) _runBufferLoop();
    }
  }
}

extension on ClipTriggerEvent {
  String get eventEmoji {
    switch (event) {
      case 'wicket': return '🎯';
      case 'four':   return '4️⃣';
      case 'six':    return '6️⃣';
      default:       return '🎬';
    }
  }
}
