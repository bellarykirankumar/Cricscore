import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class StreamViewerScreen extends StatefulWidget {
  final String matchId;
  final String matchTitle;

  const StreamViewerScreen({
    super.key,
    required this.matchId,
    required this.matchTitle,
  });

  @override
  State<StreamViewerScreen> createState() => _StreamViewerScreenState();
}

class _StreamViewerScreenState extends State<StreamViewerScreen> {
  VideoPlayerController? _controller;
  Map<String, dynamic>? _score;
  Timer? _pollTimer;
  bool _loading = true;
  bool _live = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await MatchApi.getStream(widget.matchId);
      if (info['live'] != true) {
        setState(() { _loading = false; _live = false; });
        return;
      }
      final playbackUrl = info['playbackUrl'] as String;
      final controller = VideoPlayerController.networkUrl(Uri.parse(playbackUrl));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      setState(() {
        _controller = controller;
        _live = true;
        _loading = false;
      });
      // Poll for score updates every 5s
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchScore());
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetchScore() async {
    try {
      final info = await MatchApi.getStream(widget.matchId);
      if (info['live'] != true) {
        _pollTimer?.cancel();
        setState(() { _live = false; });
        _controller?.pause();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.matchTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_live)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: Colors.white, size: 8),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)))
              : !_live
                  ? _buildOffline()
                  : Stack(children: [
                      // Video
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                      // Score overlay from timed metadata (shown if backend pushed score)
                      if (_score != null)
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: _ScoreOverlay(score: _score!),
                        ),
                      // Tap to play/pause
                      GestureDetector(
                        onTap: () {
                          if (_controller!.value.isPlaying) {
                            _controller!.pause();
                          } else {
                            _controller!.play();
                          }
                        },
                      ),
                    ]),
    );
  }

  Widget _buildOffline() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 64),
      const SizedBox(height: 16),
      const Text('Stream is not live', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text('Check back when a match is in progress', style: TextStyle(color: Colors.white54)),
      const SizedBox(height: 24),
      TextButton(
        onPressed: () { setState(() { _loading = true; }); _load(); },
        child: Text('Refresh', style: TextStyle(color: AppColors.accent)),
      ),
    ]));
  }
}

class _ScoreOverlay extends StatelessWidget {
  final Map<String, dynamic> score;
  const _ScoreOverlay({required this.score});

  @override
  Widget build(BuildContext context) {
    final team = score['battingTeam'] as String? ?? '';
    final runs = score['totalRuns'] as int? ?? 0;
    final wickets = score['totalWickets'] as int? ?? 0;
    final balls = score['totalBalls'] as int? ?? 0;
    final overs = '${balls ~/ 6}.${balls % 6}';

    return Container(
      color: Colors.black.withOpacity(0.65),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Text(
            '$team: $runs/$wickets ($overs ov)',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(3)),
          child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}
