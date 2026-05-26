import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/clip_player_widget.dart';

// ── In-memory commentary store (Phase 1) ─────────────────────
// Keyed by matchId. Entries always sorted newest-first by (innings, over, ball).
class CommentaryStore {
  CommentaryStore._();
  static final _data      = <String, List<CommentaryEntry>>{};
  // innings end summaries: matchId → { inningsNumber → summaryString }
  static final _summaries = <String, Map<int, String>>{};

  /// Add or update entry for the same (innings, over, ball) key.
  /// Inserting before AI text arrives shows the row immediately; calling again
  /// with text fills it in once the AI responds.
  static void addOrUpdate(String matchId, CommentaryEntry entry) {
    final list = _data[matchId] ??= [];
    final idx = list.indexWhere((e) =>
        e.innings == entry.innings && e.over == entry.over && e.ball == entry.ball);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    // Always keep sorted: newest first
    list.sort((a, b) {
      final ic = b.innings.compareTo(a.innings);
      if (ic != 0) return ic;
      final oc = b.over.compareTo(a.over);
      if (oc != 0) return oc;
      return b.ball.compareTo(a.ball);
    });
  }

  /// Store the end-of-innings summary (score + overs) shown in the separator.
  static void setInningsSummary(String matchId, int innings, String summary) {
    (_summaries[matchId] ??= {})[innings] = summary;
  }

  static String? getInningsSummary(String matchId, int innings) =>
      _summaries[matchId]?[innings];

  static List<CommentaryEntry> get(String matchId) =>
      List.unmodifiable(_data[matchId] ?? []);

  static void clear(String matchId) {
    _data.remove(matchId);
    _summaries.remove(matchId);
  }
}

class CommentaryEntry {
  final int innings;
  final int over;
  final int ball;
  final String batsman;
  final String bowler;
  final int runs;
  final String? extra;
  final bool isWicket;
  final String? dismissal;
  final String text; // AI commentary

  const CommentaryEntry({
    this.innings = 1,
    required this.over,
    required this.ball,
    required this.batsman,
    required this.bowler,
    required this.runs,
    this.extra,
    required this.isWicket,
    this.dismissal,
    required this.text,
  });

  String get overLabel => '$over.${ball == 0 ? 6 : ball}';

  String get eventLabel {
    if (isWicket) return 'W';
    if (extra == 'wide') return 'WD';
    if (extra == 'no_ball') return 'NB';
    if (extra == 'leg_bye') return 'LB';
    if (extra == 'bye') return 'B';
    if (runs == 0) return '•';
    return '$runs';
  }

  Color get badgeColor {
    if (isWicket) return AppColors.wicket;
    if (runs == 6) return const Color(0xFF7C3AED);
    if (runs == 4) return AppColors.four;
    if (extra != null) return AppColors.text2;
    if (runs == 0) return AppColors.bgElevated;
    return AppColors.accent.withValues(alpha: 0.7);
  }

  Color get badgeText {
    if (runs == 0 && !isWicket && extra == null) return AppColors.text2;
    return Colors.white;
  }

  String get headline =>
      '${bowler.split(' ').last.toUpperCase()} TO ${batsman.split(' ').last.toUpperCase()}, '
      '${isWicket ? 'WICKET!' : extra != null ? extra!.toUpperCase().replaceAll('_', ' ') : runs == 0 ? 'DOT BALL' : runs == 4 ? 'FOUR!' : runs == 6 ? 'SIX!' : '$runs RUN${runs != 1 ? 'S' : ''}'}';
}

// ── Commentary Screen ─────────────────────────────────────────
class CommentaryScreen extends StatefulWidget {
  final String matchId;
  final String? matchTitle;

  const CommentaryScreen({
    super.key,
    required this.matchId,
    this.matchTitle,
  });

  @override State<CommentaryScreen> createState() => _CommentaryScreenState();
}

class _CommentaryScreenState extends State<CommentaryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _filter = 'all';
  // clipKey = "innings_over_ball" → MatchClip
  Map<String, MatchClip> _clips = {};

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {
      _filter = ['all', 'boundary', 'wicket'][_tabs.index];
    }));
    _loadClips();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadClips() async {
    try {
      final clips = await ClipApi.list(widget.matchId);
      final map = <String, MatchClip>{};
      for (final c in clips) {
        if (c.event.contains('_pre') || c.event.contains('_post')) continue;
        map['${c.inningsNumber}_${c.over}_${c.ball}'] = c;
      }
      if (mounted) setState(() => _clips = map);
    } catch (_) {}
  }

  // CommentaryEntry.ball is 1-based; MatchClip.ball is 0-based.
  MatchClip? _clipFor(CommentaryEntry e) =>
      _clips['${e.innings}_${e.over}_${e.ball - 1}'];

  List<CommentaryEntry> get _entries {
    final all = CommentaryStore.get(widget.matchId);
    return switch (_filter) {
      'boundary' => all.where((e) => e.runs == 4 || e.runs == 6).toList(),
      'wicket'   => all.where((e) => e.isWicket).toList(),
      _          => all,
    };
  }

  @override Widget build(BuildContext context) {
    final entries = _entries;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.matchTitle ?? 'Commentary'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.text2,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: '4s & 6s'),
            Tab(text: 'Wickets'),
          ],
        ),
      ),
      body: entries.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final entry = entries[i];
                final nextInnings = i + 1 < entries.length ? entries[i + 1].innings : entry.innings;
                final showSeparator = entry.innings != nextInnings;
                return Column(children: [
                  CommentaryRow(entry: entry, clip: _clipFor(entry)),
                  if (showSeparator) InningsSeparator(innings: nextInnings + 1, matchId: widget.matchId),
                ]);
              },
            ),
    );
  }

  Widget _buildEmpty() {
    final isFiltered = _filter != 'all';
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(isFiltered ? '🏏' : '🎙️', style: const TextStyle(fontSize: 40)),
      const SizedBox(height: 12),
      Text(
        isFiltered
            ? 'No ${_filter == 'boundary' ? 'boundaries' : 'wickets'} yet'
            : 'No commentary yet',
        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        isFiltered
            ? 'Commentary will appear as the match progresses'
            : 'AI commentary appears here as each ball is bowled',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.text2, fontSize: 13),
      ),
    ]));
  }
}

// ── Innings Separator ─────────────────────────────────────────
class InningsSeparator extends StatelessWidget {
  final int innings;
  final String matchId;
  const InningsSeparator({required this.innings, required this.matchId});

  @override Widget build(BuildContext context) {
    // Summary for the innings that just ended (innings before this one)
    final endedInnings = innings - 1;
    final summary = endedInnings > 0
        ? CommentaryStore.getInningsSummary(matchId, endedInnings)
        : null;
    final target = innings == 2
        ? CommentaryStore.getInningsSummary(matchId, 0) // target string stored at key 0
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
            ),
            child: Text('INNINGS $innings',
              style: const TextStyle(
                color: AppColors.accent, fontSize: 11,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        ]),
        if (summary != null || target != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              if (summary != null)
                Text(summary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.text,
                    fontWeight: FontWeight.w700, fontSize: 14)),
              if (target != null) ...[
                const SizedBox(height: 4),
                Text(target,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.accent, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 4),
        ],
      ]),
    );
  }
}

// ── Single Commentary Row ─────────────────────────────────────
class CommentaryRow extends StatelessWidget {
  final CommentaryEntry entry;
  final MatchClip? clip; // optional — shown as play button when present

  const CommentaryRow({required this.entry, this.clip});

  @override Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: entry.isWicket
            ? AppColors.wicketFaint
            : entry.runs == 6
                ? const Color(0xFF7C3AED).withValues(alpha: 0.08)
                : entry.runs == 4
                    ? AppColors.four.withValues(alpha: 0.08)
                    : AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isWicket
              ? AppColors.wicket.withValues(alpha: 0.3)
              : entry.runs >= 4
                  ? entry.badgeColor.withValues(alpha: 0.25)
                  : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Over number
          SizedBox(
            width: 36,
            child: Text(entry.overLabel,
              style: const TextStyle(
                color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          // Badge
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: entry.badgeColor, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(entry.eventLabel,
              style: TextStyle(
                color: entry.badgeText,
                fontSize: entry.eventLabel.length > 1 ? 9 : 12,
                fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(entry.headline,
                    style: TextStyle(
                      color: entry.isWicket ? AppColors.wicket : AppColors.text2,
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                ),
                // Clip play button — only when a clip is available
                if (clip != null) ...[
                  const SizedBox(width: 8),
                  ClipPlayButton(clip: clip!),
                ],
              ]),
              if (entry.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(entry.text,
                  style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1.4)),
              ],
            ],
          )),
        ]),
      ),
    );
  }
}
