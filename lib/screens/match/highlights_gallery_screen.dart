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

  Widget _buildGrid(String type) {
    final clips = _filtered(type);
    if (clips.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(type == 'wicket' ? '🎯' : type == 'boundary' ? '4️⃣' : '🎬',
          style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text(
          type == 'all'
            ? 'No clips yet'
            : 'No ${type == 'wicket' ? 'wicket' : 'boundary'} clips yet',
          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Clips are recorded automatically when the scorer\nmarks a wicket or boundary',
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
