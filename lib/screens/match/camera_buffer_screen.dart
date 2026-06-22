import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../theme/app_theme.dart';
import '../../services/camera_buffer_service.dart';

// ── Camera Buffer Screen ──────────────────────────────────────
// Thin UI layer over CameraBufferService. The service owns the
// camera and buffering loop — navigating away does NOT stop recording.
//
class CameraBufferScreen extends StatefulWidget {
  final String? matchId;
  /// When embedded in a tab (e.g. home screen IndexedStack), provide this
  /// callback for the back button so it switches tabs instead of popping
  /// the navigator (which would blank the screen).
  final VoidCallback? onBack;
  const CameraBufferScreen({super.key, this.matchId, this.onBack});
  @override State<CameraBufferScreen> createState() => _CameraBufferScreenState();
}

class _CameraBufferScreenState extends State<CameraBufferScreen> {

  final _svc = CameraBufferService.instance;
  StreamSubscription? _sub;
  late final TextEditingController _matchCtrl;

  @override void initState() {
    super.initState();

    // Seed match ID from caller if provided.
    if (widget.matchId != null && widget.matchId!.isNotEmpty) {
      _svc.matchId = widget.matchId!;
    }
    _matchCtrl = TextEditingController(text: _svc.matchId);

    // Init camera if not already ready (and no error — let user retry manually).
    if (!_svc.cameraReady && !_svc.cameraError) _svc.initCamera();

    _sub = _svc.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override void dispose() {
    _sub?.cancel();
    _matchCtrl.dispose();
    // Service keeps running.
    super.dispose();
  }

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    if (!_svc.buffering) { _goBack(); return; }
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Keep buffering?', style: TextStyle(color: AppColors.text)),
        content: const Text(
          'Camera will keep recording in the background while you score.\n\n'
          'Tap "Stop & Leave" only if you want to end the recording.',
          style: TextStyle(color: AppColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep buffering', style: TextStyle(color: AppColors.accent))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop & Leave', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (leave == true) _svc.stopBuffering();
    _goBack();
  }

  Widget _buildCameraArea() {
    if (_svc.cameraReady && _svc.cam != null) {
      return AspectRatio(
        aspectRatio: _svc.cam!.value.aspectRatio,
        child: Stack(children: [
          CameraPreview(_svc.cam!),
          Positioned(
            bottom: 12, left: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                if (_svc.buffering) ...[
                  Container(width: 10, height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(_svc.status,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            ),
          ),
        ]),
      );
    }

    if (_svc.cameraError) {
      return Container(
        height: 160, color: AppColors.bgCard,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off_outlined, color: AppColors.text2, size: 36),
          const SizedBox(height: 8),
          Text(_svc.status,
            style: const TextStyle(color: AppColors.text2, fontSize: 13),
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _svc.initCamera(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ])),
      );
    }

    // Initialising
    return Container(
      height: 160, color: AppColors.bgCard,
      child: const Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }

  @override Widget build(BuildContext context) {
    // If already buffering (background), show compact status bar instead of full preview.
    final isBackgroundBuffering = _svc.buffering && (_svc.cam == null || !_svc.cameraReady);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Camera — Clip Buffer'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: _handleBack,
          ),
          actions: [
            if (_svc.buffering)
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                tooltip: 'Stop buffering',
                onPressed: _svc.stopBuffering,
              ),
          ],
        ),
        body: Column(children: [
          // Background-buffering banner (when camera was released but still recording)
          if (isBackgroundBuffering)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Container(width: 8, height: 8,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(_svc.status,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            )
          else
            _buildCameraArea(),

          Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: _matchCtrl,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                labelText: 'Match ID',
                hintText: 'Paste the match ID from the scoring screen',
                prefixIcon: Icon(Icons.sports_cricket, color: AppColors.text2),
              ),
              enabled: !_svc.buffering,
              onChanged: (v) {
                _svc.matchId = v.trim();
                setState(() {});
              },
            ),
            const SizedBox(height: 16),

            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: (!_svc.cameraReady || _svc.matchId.isEmpty)
                ? null
                : _svc.buffering
                  ? _svc.stopBuffering
                  : () => _svc.startBuffering(_svc.matchId),
              icon: Icon(_svc.buffering ? Icons.stop : Icons.fiber_manual_record),
              label: Text(_svc.buffering ? 'Stop Buffering' : 'Start Buffering'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _svc.buffering ? Colors.redAccent : AppColors.accent,
                foregroundColor: AppColors.textOnAcc,
                minimumSize: const Size(double.infinity, 52),
              ),
            )),

            const SizedBox(height: 12),

            if (!_svc.buffering)
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
                    '2. You can go back to the scoring screen — buffering continues.\n'
                    '3. When you mark a wicket or boundary, clips upload automatically.\n'
                    '4. Clips appear in the commentary timeline within seconds.',
                    style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5)),
                ]),
              ),

            if (_svc.log.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('UPLOADS', style: TextStyle(
                color: AppColors.text2, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ..._svc.log.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(l, style: const TextStyle(color: AppColors.text, fontSize: 13)),
              )),
            ],
          ])),
        ]),
      ),
    );
  }
}
