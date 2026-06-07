import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';
import '../../services/clip_ws_service.dart';
import '../../services/api_service.dart';

// ── Camera Buffer Screen ──────────────────────────────────────
// The "camera device" screen — a second phone held at the boundary.
//
// Approach: rolling pre-buffer without on-device stitching.
//   • Records 10-second segments continuously, keeps the last 3 in memory
//     (30 seconds of lookback).
//   • On WebSocket trigger: uploads the buffered segments + a 5-second
//     post-roll as separate S3 files. The clip Lambda stores them all
//     linked to the same delivery. The video player plays them sequentially.
//
class CameraBufferScreen extends StatefulWidget {
  final String? matchId;
  const CameraBufferScreen({super.key, this.matchId});
  @override State<CameraBufferScreen> createState() => _CameraBufferScreenState();
}

class _CameraBufferScreenState extends State<CameraBufferScreen>
    with WidgetsBindingObserver {

  // ── State ─────────────────────────────────────────────────────
  CameraController? _cam;
  bool   _cameraReady  = false;
  bool   _buffering    = false;
  bool   _capturing    = false; // clip capture in progress
  String _status       = 'Ready';
  String _matchId      = '';

  static const _segmentSecs  = 10; // rolling buffer chunk size
  static const _maxSegments  = 3;  // 30s of lookback
  static const _postRollSecs = 5;  // record this many seconds after the event

  final _buffer = Queue<File>(); // rolling pre-buffer
  StreamSubscription<ClipTriggerEvent>? _wsSub;
  final _matchCtrl = TextEditingController();

  ClipTriggerEvent? _pendingTrigger;
  final _log = <String>[]; // on-screen upload log

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _matchId = widget.matchId ?? '';
    _matchCtrl.text = _matchId;
    _initCamera();
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopBuffering();
    _cam?.dispose();
    _wsSub?.cancel();
    ClipWsService.instance.disconnect();
    _matchCtrl.dispose();
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopBuffering();
      _cam!.dispose();
      _cam = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera init ───────────────────────────────────────────────
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) { setState(() => _status = 'No camera found'); return; }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(back, ResolutionPreset.high, enableAudio: true);
    await ctrl.initialize();
    if (mounted) setState(() { _cam = ctrl; _cameraReady = true; });
  }

  // ── Buffering loop ────────────────────────────────────────────
  Future<void> _startBuffering() async {
    if (_buffering || _cam == null || !_cam!.value.isInitialized) return;
    setState(() { _buffering = true; _status = '🔴 Buffering…'; });
    ClipWsService.instance.setBuffering(true);
    _buffer.clear();

    if (_matchId.isNotEmpty) {
      await ClipWsService.instance.connect(_matchId);
      _wsSub?.cancel();
      _wsSub = ClipWsService.instance.onTrigger.listen(_onTrigger);
    }

    while (_buffering) {
      // Pause the loop while a clip capture is in progress — _captureAndUpload
      // stops the current recording itself and restarts after upload.
      if (_capturing) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      // Guard: don't double-start if camera is already recording.
      if (_cam!.value.isRecordingVideo) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }
      try {
        await _cam!.startVideoRecording();
        await Future.delayed(const Duration(seconds: _segmentSecs));
        if (!_buffering || _capturing) {
          // Capture took over mid-segment — let _captureAndUpload handle stop.
          break;
        }
        final xFile = await _cam!.stopVideoRecording();
        final seg = File(xFile.path);

        if (_buffer.length >= _maxSegments) {
          final old = _buffer.removeFirst();
          try { old.deleteSync(); } catch (_) {}
        }
        _buffer.addLast(seg);

        // Process any pending trigger that arrived while we were finishing a segment
        if (_pendingTrigger != null) {
          final t = _pendingTrigger!;
          _pendingTrigger = null;
          unawaited(_captureAndUpload(t));
        }
      } catch (e) {
        if (_buffering) {
          setState(() => _status = 'Camera error: $e');
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  void _stopBuffering() {
    if (!_buffering) return;
    setState(() { _buffering = false; _status = 'Stopped'; });
    ClipWsService.instance.setBuffering(false);
    _wsSub?.cancel();
    _wsSub = null;
    ClipWsService.instance.disconnect();
  }

  // ── WebSocket trigger handler ─────────────────────────────────
  void _onTrigger(ClipTriggerEvent t) {
    if (_capturing) {
      _pendingTrigger = t; // handle after current upload
      return;
    }
    unawaited(_captureAndUpload(t));
  }

  // ── Capture post-roll + upload all segments ───────────────────
  Future<void> _captureAndUpload(ClipTriggerEvent t) async {
    if (_capturing || _cam == null) return;
    setState(() { _capturing = true; _status = '🎬 Capturing post-roll…'; });

    // Snapshot current buffer, then stop any in-flight buffer segment so
    // we can start post-roll cleanly (avoids "already recording" exception).
    final preSegments = _buffer.toList();
    if (_cam!.value.isRecordingVideo) {
      try {
        final xFile = await _cam!.stopVideoRecording();
        preSegments.add(File(xFile.path)); // include the partial segment
      } catch (_) {}
    }

    try {
      // Record 5 seconds after the event
      await _cam!.startVideoRecording();
      await Future.delayed(const Duration(seconds: _postRollSecs));
      final postXFile = await _cam!.stopVideoRecording();
      final postFile  = File(postXFile.path);

      final allSegments = [...preSegments, postFile];
      final totalDurationMs = allSegments.length * _segmentSecs * 1000;

      setState(() => _status = '☁️ Uploading ${allSegments.length} segments…');

      // Upload each segment as a separate S3 file under the same clipId prefix
      for (var i = 0; i < allSegments.length; i++) {
        final seg = allSegments[i];
        final isPost = i == allSegments.length - 1;
        final segEvent = isPost ? '${t.event}_post' : '${t.event}_pre${i + 1}';

        final presign = await ClipApi.presign(
          matchId:      t.matchId,
          inningsNumber:t.inningsNumber,
          over:          t.over,
          ball:          t.ball,
          event:         segEvent,
        );

        final bytes = await seg.readAsBytes();
        final res = await http.put(
          Uri.parse(presign.uploadUrl),
          headers: {'Content-Type': 'video/mp4'},
          body: bytes,
        );
        if (res.statusCode != 200) throw Exception('S3 upload $i failed: ${res.statusCode}');

        // Save the first segment as the primary clip record
        if (i == 0) {
          await ClipApi.save(
            matchId:      t.matchId,
            inningsNumber:t.inningsNumber,
            over:          t.over,
            ball:          t.ball,
            event:         t.event,
            s3Key:         presign.s3Key,
            durationMs:    totalDurationMs,
          );
        }
      }

      // Clean up
      for (final f in [...preSegments, postFile]) {
        try { f.deleteSync(); } catch (_) {}
      }
      _buffer.clear();

      final label = '${t.eventEmoji} ${t.event} @ ${t.over}.${t.ball + 1} — ${allSegments.length} segments';
      setState(() {
        _capturing = false;
        _status = '✅ Uploaded';
        _log.insert(0, label);
      });
    } catch (e) {
      setState(() { _capturing = false; _status = '❌ Upload failed: $e'; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Camera — Clip Buffer'),
        actions: [
          if (_buffering)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              tooltip: 'Stop',
              onPressed: _stopBuffering,
            ),
        ],
      ),
      body: Column(children: [
        // Camera preview
        if (_cameraReady && _cam != null)
          AspectRatio(
            aspectRatio: _cam!.value.aspectRatio,
            child: Stack(children: [
              CameraPreview(_cam!),
              Positioned(
                bottom: 12, left: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    if (_buffering) ...[
                      Container(width: 10, height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: Text(_status,
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
                    if (_buffer.isNotEmpty)
                      Text('${_buffer.length}×${_segmentSecs}s',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ]),
                ),
              ),
            ]),
          )
        else
          Container(height: 220, color: AppColors.bgCard,
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.accent))),

        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _matchCtrl,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Match ID',
              hintText: 'Paste the match ID from the scoring screen',
              prefixIcon: Icon(Icons.sports_cricket, color: AppColors.text2),
            ),
            onChanged: (v) => setState(() => _matchId = v.trim()),
          ),
          const SizedBox(height: 16),

          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: (!_cameraReady || _matchId.isEmpty)
              ? null
              : _buffering ? _stopBuffering : _startBuffering,
            icon: Icon(_buffering ? Icons.stop : Icons.fiber_manual_record),
            label: Text(_buffering ? 'Stop Buffering' : 'Start Buffering'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _buffering ? Colors.redAccent : AppColors.accent,
              foregroundColor: AppColors.textOnAcc,
              minimumSize: const Size(double.infinity, 52),
            ),
          )),

          const SizedBox(height: 12),

          if (!_buffering)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('How it works', style: TextStyle(
                  color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
                SizedBox(height: 6),
                Text(
                  '1. Enter the match ID and tap Start Buffering.\n'
                  '2. Keep the phone pointed at the pitch — it silently records a 30-second rolling buffer.\n'
                  '3. When the scorer marks a wicket or boundary, clips upload automatically.\n'
                  '4. Clips appear in the commentary timeline within seconds.',
                  style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5)),
              ]),
            ),

          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('UPLOADS', style: TextStyle(
              color: AppColors.text2, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            ..._log.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(l, style: const TextStyle(color: AppColors.text, fontSize: 13)),
            )),
          ],
        ])),
      ]),
    );
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
