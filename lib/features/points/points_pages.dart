import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/brand_motion.dart';
import '../../shared/widgets.dart';

/// Pack Points 2.0. Read-only: the server is authoritative and awards come
/// only from verified activity. Pending points are never shown as confirmed,
/// and nothing is shown while V2 is not live.
class PointsPage extends StatefulWidget {
  const PointsPage({super.key});
  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  late Future<List<dynamic>> load = _load();

  Future<List<dynamic>> _load() async {
    final api = repository(context);
    final me = asJson(await api.request('points/me'));
    final rules = asJson(await api.request('points/rules'));
    if (me['enabled'] != true) return [me, rules, null, null];
    final history = asJson(await api.request('points/me/history'));
    final board = asJson(await api.request('points/leaderboard', query: {'board': 'users', 'scope': 'season'}));
    return [me, rules, history, board];
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<dynamic>>(
    future: load,
    builder: (c, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Center(child: MoonPulseLoader(label: 'Counting your points'));
      }
      if (snap.hasError) {
        return ErrorPanel(snap.error.toString(), retry: () => setState(() => load = _load()));
      }
      final [me as Json, rules as Json, history as Json?, board as Json?] = snap.data!;
      return RefreshIndicator(
        onRefresh: () async => setState(() => load = _load()),
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const PageHeading('Pack Points', 'Earned for genuine contributions, confirmed by TWON.'),
            if (me['enabled'] != true) ...[
              const _Notice(
                title: 'Pack Points 2.0 isn’t live yet',
                body: 'Your points will appear here once the new, fairer points system is switched on.',
              ),
            ] else ...[
              _Totals(me),
              if (me['clan'] is Map) _ClanCard(asJson(me['clan'])),
              const SizedBox(height: 16),
              Text('Your history', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...asRows(history?['items']).map((i) => _HistoryTile(i)),
              if (asRows(history?['items']).isEmpty)
                const _Notice(title: 'No points yet', body: 'Post, comment or share an approved Pack Look to start earning.'),
              const SizedBox(height: 16),
              Text('Leaderboard · this season', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...asRows(board?['items']).map((r) => _RankTile(r)),
            ],
            const SizedBox(height: 16),
            _HowItWorks(rules),
          ],
        ),
      );
    },
  );
}

int _int(Object? v) => v is num ? v.toInt() : 0;

class _Totals extends StatelessWidget {
  const _Totals(this.me);
  final Json me;
  @override
  Widget build(BuildContext c) {
    final season = asJson(me['season']);
    final lifetime = asJson(me['lifetime']);
    Widget stat(String label, String value, String hint, {bool accent = false}) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(c).textTheme.labelMedium?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: accent ? Theme.of(c).colorScheme.primary : null)),
              Text(hint, style: Theme.of(c).textTheme.bodySmall?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
    final rank = season['rank'];
    return Column(
      children: [
        Row(children: [
          stat('Season ${season['id']}', '${_int(season['confirmed'])} XP', rank == null ? 'Not ranked yet' : 'Rank #$rank', accent: true),
          const SizedBox(width: 8),
          stat('Pending review', '${_int(season['pending'])} XP', 'Not counted until confirmed'),
        ]),
        Row(children: [
          stat('All time', '${_int(lifetime['confirmed'])} XP', 'Confirmed points'),
          const SizedBox(width: 8),
          stat('Reversed', '${_int(lifetime['reversed'])} XP', 'Removed or ineligible'),
        ]),
      ],
    );
  }
}

class _ClanCard extends StatelessWidget {
  const _ClanCard(this.clan);
  final Json clan;
  @override
  Widget build(BuildContext c) {
    final season = asJson(clan['season']);
    final rank = clan['rank'];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shield_outlined, color: TwonPalette.moonBlue),
        title: Text(clan['name']?.toString() ?? 'Your clan', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_int(season['contributors'])} active contributors · ${rank == null ? 'not ranked yet' : 'rank #$rank'}'
            '${_int(season['pending']) > 0 ? ' · +${_int(season['pending'])} pending' : ''}'),
        trailing: Text('${_int(season['confirmed'])} CP', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

const _sourceLabels = {
  'post': 'Original post',
  'comment': 'Comment',
  'lookbook': 'Approved Pack Look',
  'event_attendance': 'Verified gathering attendance',
  'admin_adjustment': 'Adjustment by the TWON team',
  'legacy_opening': 'Points carried over',
};

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.item);
  final Json item;
  @override
  Widget build(BuildContext c) {
    final kind = item['kind']?.toString();
    final status = item['status']?.toString();
    final voided = kind == 'award' && status == 'reversed' && item['confirmedAt'] == null;
    final label = kind == 'reversal'
        ? 'Reversed'
        : status == 'pending'
        ? 'Pending review'
        : voided
        ? 'Not awarded'
        : status == 'reversed'
        ? 'Later reversed'
        : 'Confirmed';
    final xp = _int(item['userXp']);
    final cp = _int(item['clanCp']);
    final source = _sourceLabels[item['sourceType']] ?? item['sourceType']?.toString() ?? '';
    final scheme = Theme.of(c).colorScheme;
    return Semantics(
      label: '$label: ${kind == 'reversal' ? 'reversed ' : ''}$source, ${xp > 0 ? '+' : ''}$xp XP',
      excludeSemantics: true,
      child: Card(
        child: ListTile(
          leading: Icon(
            kind == 'reversal' ? Icons.undo_rounded : status == 'pending' ? Icons.schedule_rounded : Icons.military_tech_outlined,
            color: xp < 0 ? scheme.error : scheme.primary,
          ),
          title: Text(kind == 'reversal' ? 'Reversed: $source' : source),
          subtitle: Text('$label · ${dateLabel(item['occurredAt']?.toString() ?? '')}'),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${xp > 0 ? '+' : ''}$xp XP',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: voided ? scheme.onSurfaceVariant : xp < 0 ? scheme.error : null,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
              if (cp != 0) Text('${cp > 0 ? '+' : ''}$cp CP', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile(this.row);
  final Json row;
  @override
  Widget build(BuildContext c) => ListTile(
    leading: SizedBox(
      width: 32,
      child: Text('${row['rank']}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: _int(row['rank']) <= 3 ? Theme.of(c).colorScheme.primary : null)),
    ),
    title: Text(row['name']?.toString() ?? ''),
    subtitle: Text('@${row['handle']}'),
    trailing: Text('${_int(row['points'])} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks(this.rules);
  final Json rules;
  @override
  Widget build(BuildContext c) {
    final r = asJson(rules['rules']);
    Widget row(String key, String name) {
      final rule = asJson(r[key]);
      final enabled = rule['enabled'] == true;
      return ListTile(
        dense: true,
        enabled: enabled,
        title: Text(name),
        subtitle: Text(enabled ? 'Confirmed after ${_int(rule['holdHours'])} h if still eligible' : (rule['disabledReason']?.toString() ?? 'Not active yet')),
        trailing: Text(enabled ? '+${_int(rule['userXp'])} XP${_int(rule['clanCp']) > 0 ? ' · +${_int(rule['clanCp'])} CP' : ''}' : '—'),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('How points work', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            row('post', 'Original public post'),
            row('comment', 'Comment on someone else’s post'),
            row('lookbook', 'Pack Look approved by moderators'),
            row('event_attendance', 'Verified gathering attendance'),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Points come from what actually happened on TWON, never from your device. Clan points go to the clan you were in at the time and stay there if you move. Removed content loses its points. Likes, follows and logins don’t earn points. Days and seasons use UTC.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
        ],
      ),
    ),
  );
}
