import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/clip_player_widget.dart';

// ── Highlights Gallery Screen ─────────────────────────────────
// Shows all clips for a match, grouped by event type.
// Accessible from the scorecard (Highlights button).
class HighlightsGalleryScreen extends StatefulWidget {
  final String matchId;
  final String? matchTitle;

  const HighlightsGalleryScreen({
    super.key,
    required this.matchId,
    this.matchTitle,
  });

  @override State<HighlightsGalleryScreen> createState() => _HighlightsGalleryScreenState();
}

class _HighlightsGalleryScreenState extends State<HighlightsGalleryScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;
  List<MatchClip> _all      = [];
  bool _loading = true;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final clips = await ClipApi.list(widget.matchId);
      // Filter out segment files (pre1, pre2, post suffixes)
      final primary = clips.where((c) =>
        !c.event.contains('_pre') && !c.event.contains('_post')).toList();
      if (mounted) setState(() { _all = primary; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MatchClip> _filtered(String type) {
    return switch (type) {
      'wicket'   => _all.where((c) => c.event == 'wicket').toList(),
      'boundary' => _all.where((c) => c.event == 'four' || c.event == 'six').toList(),
      _          => _all,
    };
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.matchTitle != null ? '${widget.matchTitle} — Highlights' : 'Highlights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.text2,
          tabs: [
            Tab(text: 'All (${_all.length})'),
            Tab(text: 'Wickets 🎯'),
            Tab(text: 'Boundaries'),
          ],
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : TabBarView(
            controller: _tabs,
            children: [
              _buildGrid('all'),
              _buildGrid('wicket'),
              _buildGrid('boundary'),
            ],
          ),
    );
  }

  Widget _setupStep(IconData icon, String title, String desc) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: AppColors.accent),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
          color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(desc, style: const TextStyle(
          color: AppColors.text2, fontSize: 12, height: 1.45)),
      ])),
    ]);
  }

  Widget _buildGrid(String type) {
    final clips = _filtered(type);
    if (clips.isEmpty) {
      if (type == 'all') {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎬', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            const Text('No clips yet', style: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Clips are saved automatically when the scorer marks a wicket, four, or six — no manual recording needed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2, fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            // How to set up
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('How to set up', style: TextStyle(
                    color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('BETA', style: TextStyle(
                      color: AppColors.textOnAcc, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                  ),
                ]),
                const SizedBox(height: 14),
                _setupStep(Icons.phone_android_outlined, 'Camera device',
                  'Open CricScore on a second phone. Tap the 📹 icon in the scoring screen and enter the Match ID shown there.'),
                const SizedBox(height: 12),
                _setupStep(Icons.sports_cricket_outlined, 'Score as usual',
                  'When the scorer marks a wicket, four, or six, a 15-second clip is saved automatically.'),
                const SizedBox(height: 12),
                _setupStep(Icons.video_library_outlined, 'View & share',
                  'Clips appear here in the Highlights tab. Tap any clip to play it.'),
              ]),
            ),
          ]),
        );
      }
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(type == 'wicket' ? '🎯' : '4️⃣',
          style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('No ${type == 'wicket' ? 'wicket' : 'boundary'} clips yet',
          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Clips are recorded automatically\nwhen the scorer marks a wicket or boundary',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.text2, fontSize: 13)),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: clips.length,
        itemBuilder: (_, i) => HighlightCard(clip: clips[i]),
      ),
    );
  }
}
