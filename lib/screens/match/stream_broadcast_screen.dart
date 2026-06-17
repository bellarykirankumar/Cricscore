import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:haishin_kit/haishin_kit.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class StreamBroadcastScreen extends StatefulWidget {
  final String matchId;
  final String matchTitle;

  const StreamBroadcastScreen({
    super.key,
    required this.matchId,
    required this.matchTitle,
  });

  @override
  State<StreamBroadcastScreen> createState() => _StreamBroadcastScreenState();
}

class _StreamBroadcastScreenState extends State<StreamBroadcastScreen> {
  MediaMixer? _mixer;
  StreamSession? _session;
  TextScreenObject? _scoreOverlay;

  bool _starting = false;
  bool _live = false;
  String? _error;
  String? _playbackUrl;

  @override
  void dispose() {
    _mixer?.dispose();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _startStream() async {
    setState(() { _starting = true; _error = null; });
    try {
      // Get RTMP credentials from backend
      final info = await MatchApi.startStream(widget.matchId);
      final ingestEndpoint = info['ingestEndpoint'] as String;
      final streamKey = info['streamKey'] as String;
      _playbackUrl = info['playbackUrl'] as String?;

      // IVS RTMPS URL: rtmps://<ingest>:443/app/<key>
      final rtmpsUrl = '$ingestEndpoint$streamKey';

      // Configure iOS audio session
      final audioSession = await AudioSession.instance;
      await audioSession.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
      ));

      final videoSources = await HaishinKitPlatformInterface.instance.videoSources;
      if (videoSources.isEmpty) throw Exception('No camera found');

      final mixer = await MediaMixer.create(
        options: MediaMixerOptions(captureSessionMode: CaptureSessionMode.multi),
      );
      await mixer.attachAudio(0, AudioSource());
      await mixer.attachVideo(0, videoSources.first);

      // Score overlay burned into stream
      final text = TextScreenObject();
      text.value = '';
      text.verticalAlignment = VerticalAlignment.bottom;
      text.horizontalAlignment = HorizontalAlignment.left;
      text.layoutMargin = ScreenObjectEdgeInsets(top: 0, left: 16, bottom: 32, right: 0);
      text.fontSize = 48;
      mixer.screen?.addChild(text);
      _scoreOverlay = text;

      await mixer.startRunning();

      final session = await StreamSession.create(rtmpsUrl, StreamSessionMode.publish);
      await session.connect();

      setState(() {
        _mixer = mixer;
        _session = session;
        _live = true;
        _starting = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _starting = false; });
    }
  }

  Future<void> _stopStream() async {
    await _session?.close();
    await MatchApi.stopStream(widget.matchId);
    setState(() { _live = false; _playbackUrl = null; });
  }

  void updateScore(String scoreText) {
    _scoreOverlay?.value = scoreText;
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
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: Colors.white, size: 8),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
        ],
      ),
      body: Stack(children: [
        // Camera preview
        if (_session != null)
          Center(child: StreamSessionViewTexture(_session))
        else
          const Center(child: Icon(Icons.videocam_outlined, color: Colors.white38, size: 80)),

        // Error
        if (_error != null)
          Positioned(
            top: 16, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade900, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),

        // Share link when live
        if (_live && _playbackUrl != null)
          Positioned(
            bottom: 100, left: 16, right: 16,
            child: GestureDetector(
              onTap: () {
                // Viewer link is the app deep link
                final link = 'cricscore://watch/${widget.matchId}';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Share: $link'), duration: const Duration(seconds: 3)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.link, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Tap to copy viewer link', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ),
            ),
          ),

        // Start / Stop button
        Positioned(
          bottom: 32, left: 0, right: 0,
          child: Center(
            child: _starting
                ? const CircularProgressIndicator(color: Colors.white)
                : ElevatedButton.icon(
                    onPressed: _live ? _stopStream : _startStream,
                    icon: Icon(_live ? Icons.stop : Icons.play_arrow),
                    label: Text(_live ? 'Stop Stream' : 'Go Live'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _live ? Colors.red : AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}
