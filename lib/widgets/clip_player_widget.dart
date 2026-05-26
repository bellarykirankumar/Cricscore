import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

// ── Clip Play Button ──────────────────────────────────────────
// Compact button shown on a commentary row when a clip exists.
// Tap → opens ClipPlayerScreen as a modal.
class ClipPlayButton extends StatelessWidget {
  final MatchClip clip;
  const ClipPlayButton({super.key, required this.clip});

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPlayer(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_circle_outline, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text('Clip', style: TextStyle(
            fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  void _openPlayer(BuildContext context) {
    if (clip.playUrl == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ClipPlayerScreen(clip: clip),
    ));
  }
}

// ── Full-Screen Clip Player ───────────────────────────────────
class ClipPlayerScreen extends StatefulWidget {
  final MatchClip clip;
  const ClipPlayerScreen({super.key, required this.clip});
  @override State<ClipPlayerScreen> createState() => _ClipPlayerScreenState();
}

class _ClipPlayerScreenState extends State<ClipPlayerScreen> {
  VideoPlayerController? _ctrl;
  bool _initialised = false;
  bool _error       = false;

  @override void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final url = widget.clip.playUrl;
    if (url == null) { setState(() => _error = true); return; }
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.initialize();
      ctrl.setLooping(false);
      await ctrl.play();
      if (mounted) setState(() { _ctrl = ctrl; _initialised = true; });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.clip.eventEmoji} ${widget.clip.event.replaceAll('_', ' ').toUpperCase()} · Over ${widget.clip.overDotBall}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Center(
        child: _error
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              const Text('Could not load clip', style: TextStyle(color: Colors.white54)),
            ])
          : !_initialised
            ? const CircularProgressIndicator(color: Colors.white)
            : GestureDetector(
                onTap: () {
                  _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
                  setState(() {});
                },
                child: AspectRatio(
                  aspectRatio: _ctrl!.value.aspectRatio,
                  child: Stack(alignment: Alignment.center, children: [
                    VideoPlayer(_ctrl!),
                    // Progress bar
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: VideoProgressIndicator(_ctrl!,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: AppColors.accent,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                    // Play/pause overlay
                    if (!_ctrl!.value.isPlaying)
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 32),
                      ),
                  ]),
                ),
              ),
      ),
    );
  }
}

// ── Highlights Thumbnail Card ─────────────────────────────────
// Used in the highlights gallery grid.
class HighlightCard extends StatelessWidget {
  final MatchClip clip;
  const HighlightCard({super.key, required this.clip});

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ClipPlayerScreen(clip: clip),
      )),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Thumbnail placeholder
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Container(
                color: AppColors.bgElevated,
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(clip.eventEmoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 6),
                  Icon(Icons.play_circle_outline, color: AppColors.accent, size: 28),
                ])),
              ),
            ),
          ),
          // Caption
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                clip.event.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  color: AppColors.accent, fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
              const SizedBox(height: 2),
              Text('Over ${clip.overDotBall}',
                style: const TextStyle(color: AppColors.text2, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
