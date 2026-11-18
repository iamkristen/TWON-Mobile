import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme.dart';
import '../../core/models.dart';
import '../../core/env_config.dart';
import '../../shared/forms.dart';
import '../../shared/widgets.dart';
import '../auth/auth_cubit.dart';
import '../../shared/csv.dart';

class GatheringsPage extends StatefulWidget {
  const GatheringsPage({super.key});
  @override
  State<GatheringsPage> createState() => _GatheringsPageState();
}

class _GatheringsPageState extends State<GatheringsPage> {
  String q = '', period = 'upcoming', category = '';
  Future<void> filters() async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GatheringFilters(period: period, category: category),
    );
    if (result != null && mounted) {
      setState(() {
        period = result.$1;
        category = result.$2;
      });
    }
  }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search gatherings',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (v) => setState(() => q = v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Filter gatherings',
              onPressed: filters,
              icon: Badge(
                isLabelVisible: period != 'upcoming' || category.isNotEmpty,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
            const SizedBox(width: 8),
            ResourcePanel(
              path: 'clans/me',
              compact: true,
              builder: (d, myClan, r) =>
                  myClan.object('membership')['canHostEvents'] == true
                  ? IconButton.filled(
                      tooltip: 'Publish gathering',
                      style: TwonButtonStyles.filledIcon(),
                      onPressed: () => c.push('/events/new'),
                      icon: const Icon(Icons.add_rounded),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      if (period != 'upcoming' || category.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                if (period != 'upcoming')
                  InputChip(
                    label: Text(period == 'past' ? 'Past' : 'All dates'),
                    onDeleted: () => setState(() => period = 'upcoming'),
                  ),
                if (category.isNotEmpty)
                  InputChip(
                    label: Text(category),
                    onDeleted: () => setState(() => category = ''),
                  ),
              ],
            ),
          ),
        ),
      Expanded(
        child: CollectionView(
          key: ValueKey('$q:$period:$category'),
          path: 'events',
          emptyAsset: 'pack-gathering',
          query: {
            'period': period,
            if (q.isNotEmpty) 'q': q,
            if (category.isNotEmpty) 'category': category,
          },
          empty: 'No gatherings match your filters.',
          builder: (d, event, r) => Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => c.push('/events/${event.id}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.text('image').isNotEmpty) ...[
                      BrandImage(event.text('image'), width: double.infinity),
                      const SizedBox(height: 12),
                    ],
                    // Date first, in the brand accent: it is what people scan for.
                    Text(
                      eventWhen(event.data),
                      style: Theme.of(c).textTheme.labelLarge?.copyWith(
                        color: Theme.of(c).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.text('phase') == 'cancelled'
                          ? 'Cancelled · ${event.text('title')}'
                          : event.text('title'),
                      style: Theme.of(c).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: event.text('phase') == 'cancelled'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _EventFact(Icons.place_outlined, event.text('location')),
                    _EventFact(
                      Icons.group_outlined,
                      '${event.number('attendeeCount')} attending',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class GatheringFilters extends StatefulWidget {
  const GatheringFilters({
    super.key,
    required this.period,
    required this.category,
  });
  final String period, category;
  @override
  State<GatheringFilters> createState() => _GatheringFiltersState();
}

class _GatheringFiltersState extends State<GatheringFilters> {
  late String period = widget.period;
  late final category = TextEditingController(text: widget.category);
  @override
  void dispose() {
    category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(c).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Filters',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  period = 'upcoming';
                  category.clear();
                }),
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(period),
            initialValue: period,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'When'),
            items: const [
              DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
              DropdownMenuItem(value: 'past', child: Text('Past')),
              DropdownMenuItem(value: 'all', child: Text('All dates')),
            ],
            onChanged: (v) => setState(() => period = v!),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: category,
            decoration: const InputDecoration(
              labelText: 'Category',
              hintText: 'Any category',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(c, (period, category.text.trim())),
            child: const Text('Show gatherings'),
          ),
        ],
      ),
    ),
  );
}

class GatheringPage extends StatelessWidget {
  const GatheringPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) => DetailView(
    path: 'events/$id',
    builder: (d, event, refresh) {
      final userId = c.read<AuthCubit>().userId;
      final attending = (event.data['attendees'] as List? ?? []).any(
        (v) => entityId(v) == userId,
      );
      // G4 (handoff C): the server's phase and rsvpOpen decide.
      final rsvp = rsvpState(event.data, attending: attending);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (event.text('image').isNotEmpty)
            BrandImage(event.text('image'), width: double.infinity),
          const SizedBox(height: 20),
          PageHeading(event.text('title'), eventWhen(event.data)),
          if (event.text('phase') == 'cancelled')
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_busy),
                title: const Text('This gathering was cancelled'),
                subtitle: event.text('cancelReason').isEmpty
                    ? null
                    : Text(event.text('cancelReason')),
              ),
            ),
          Text(event.text('description')),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(event.text('location')),
            subtitle: Text(
              event.object('clan')['name']?.toString() ?? 'Pack gathering',
            ),
          ),
          Text('${event.number('attendeeCount')} members attending'),
          const SizedBox(height: 16),
          if (rsvp.action == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                rsvp.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else
            ActionButton(
              label: rsvp.label,
              action: () => repository(c).request(
                'events/$id/attend',
                method: rsvp.action == 'leave' ? 'DELETE' : 'POST',
              ),
              onSuccess: (_) => refresh(),
            ),
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: '${AppConfig.websiteUrl}/events/$id'),
            ),
            icon: const Icon(Icons.share),
            label: const Text('Share gathering'),
          ),
          ResourcePanel(
            path: 'clans/me',
            builder: (m, self, r) {
              final allowed =
                  self.object('membership')['canHostEvents'] == true &&
                  entityId(self.data['clan']) == event.text('clanId');
              return !allowed
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: const Text('Edit gathering'),
                          onTap: () =>
                              c.push('/events/$id/edit', extra: event.data),
                        ),
                        if (entityId(event.data['organizerId']) == userId)
                          ActionButton(
                            label: 'Export attendee list',
                            tonal: true,
                            action: () async {
                              final attendees = asRows(
                                await repository(
                                  c,
                                ).request('events/$id/attendees'),
                              );
                              // SEC-012: no contact data; formula-safe CSV.
                              final csv = attendeeCsv(attendees);
                              await SharePlus.instance.share(
                                ShareParams(
                                  text: csv,
                                  title: 'Gathering attendees',
                                ),
                              );
                            },
                          ),
                        if (event.text('phase') == 'upcoming')
                          TextButton(
                            onPressed: () => showModalBottomSheet(
                              context: c,
                              isScrollControlled: true,
                              builder: (sheet) => SizedBox(
                                height: 360,
                                child: FeatureForm(
                                  title: 'Cancel this gathering',
                                  button: 'Cancel gathering',
                                  fields: const [
                                    FieldSpec(
                                      'reason',
                                      'Reason (shown to everyone registered)',
                                      kind: FieldKind.multiline,
                                      maxLength: 500,
                                    ),
                                  ],
                                  submit: (v) => repository(c).request(
                                    'events/$id/cancel',
                                    method: 'POST',
                                    body: {
                                      'reason': '${v['reason'] ?? ''}'.trim(),
                                    },
                                  ),
                                  onSuccess: (_) {
                                    Navigator.pop(sheet);
                                    refresh();
                                  },
                                ),
                              ),
                            ),
                            child: const Text('Cancel gathering'),
                          ),
                        ActionButton(
                          label: 'Delete gathering',
                          tonal: true,
                          confirmation:
                              'Remove this gathering for everyone? If people registered, it is cancelled instead and kept.',
                          action: () => repository(
                            c,
                          ).request('events/$id', method: 'DELETE'),
                          // G4: with registrations it is cancelled, not deleted.
                          onSuccess: (result) =>
                              asJson(result)['cancelled'] == true
                              ? refresh()
                              : c.pop(),
                        ),
                      ],
                    );
            },
          ),
        ],
      );
    },
  );
}

class GatheringEditor extends StatelessWidget {
  const GatheringEditor({super.key, this.id, this.initial});
  final String? id;
  final Json? initial;
  @override
  Widget build(BuildContext c) => FeatureForm(
    title: id == null ? 'Bring the pack together' : 'Edit gathering',

    button: id == null ? 'Publish gathering' : 'Save changes',
    fields: [
      FieldSpec('title', 'Title', initial: initial?['title'], maxLength: 200),
      FieldSpec(
        'description',
        'About the gathering',
        kind: FieldKind.multiline,
        initial: initial?['description'],
        maxLength: 10000,
      ),
      FieldSpec('category', 'Category', initial: initial?['category']),
      // G4 (handoff C): in the gathering's own zone; fixed once started.
      if (scheduleEditable(initial)) ...[
        FieldSpec(
          'date',
          'Date',
          kind: FieldKind.date,
          initial: initial?['date']?.toString().split('T').first,
        ),
        FieldSpec(
          'time',
          'Start time (in the gathering\'s time zone)',
          kind: FieldKind.time,
          initial: initial?['time'],
        ),
        FieldSpec(
          'endTime',
          'End time (in the gathering\'s time zone)',
          kind: FieldKind.time,
          required: false,
          initial: initial?['endTime'],
        ),
        FieldSpec(
          'timeZone',
          'Time zone',
          kind: FieldKind.select,
          options: timeZoneOptions(initial),
          initial: (initial?['timeZoneSource'] == 'organizer')
              ? initial!['timeZone']
              : null,
        ),
      ],
      FieldSpec('location', 'Location', initial: initial?['location']),
      FieldSpec(
        'image',
        'Cover photo',
        kind: FieldKind.image,
        required: false,
        initial: initial?['image'],
      ),
    ],
    submit: (v) {
      if (v['endTime'] != null &&
          '${v['endTime']}'.isNotEmpty &&
          '${v['endTime']}'.compareTo('${v['time']}') <= 0) {
        throw const AppFailure(
          'End time must be after the start time on the same day.',
        );
      }
      return repository(c).request(
        id == null ? 'events' : 'events/$id',
        method: id == null ? 'POST' : 'PATCH',
        body: v,
      );
    },
    onSuccess: (_) => c.pop(),
  );
}

/// One muted icon + text line on a gathering card (location, attendance).
class _EventFact extends StatelessWidget {
  const _EventFact(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext c) {
    final muted = Theme.of(c).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(color: muted)),
          ),
        ],
      ),
    );
  }
}

/// G4 (handoff C): IANA time zones offered to organisers (the id is sent as chosen).
const gatheringTimeZones = [
  'Asia/Kathmandu',
  'Europe/London',
  'Europe/Dublin',
  'Europe/Paris',
  'Europe/Berlin',
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Hong_Kong',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Australia/Sydney',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'UTC',
];
List<String> timeZoneOptions(Json? initial) {
  final current = initial?['timeZone']?.toString();
  return [
    if (current != null &&
        current.isNotEmpty &&
        !gatheringTimeZones.contains(current))
      current,
    ...gatheringTimeZones,
  ];
}

/// Date, wall-clock time and zone exactly as the organiser set them (no UTC guess).
String eventWhen(Json e) {
  final date = dateLabel('${e['date'] ?? ''}');
  final time = '${e['time'] ?? ''}';
  final end = '${e['endTime'] ?? ''}';
  final zone = '${e['timeZone'] ?? ''}';
  final when =
      '$date · $time${end.isNotEmpty ? '–$end' : ''}${zone.isNotEmpty ? ' ($zone)' : ''}';
  return e['timeZoneAssumed'] == true
      ? '$when · time zone not confirmed'
      : when;
}

/// The schedule (date, time, zone) can change only before the gathering starts.
bool scheduleEditable(Json? e) =>
    e == null || e['phase'] == null || e['phase'] == 'upcoming';

/// G4 (handoff C): what the RSVP control shows, from the server's phase, rsvpOpen and spotsLeft.
({String label, String? action}) rsvpState(Json e, {required bool attending}) {
  final phase = '${e['phase'] ?? 'upcoming'}';
  final open = e['rsvpOpen'] != false;
  final full = e['spotsLeft'] == 0;
  if (attending && (open || phase == 'cancelled')) {
    return (label: 'Cancel RSVP', action: 'leave');
  }
  if (!attending && open && !full && phase == 'upcoming') {
    return (label: 'Join gathering', action: 'join');
  }
  if (phase == 'cancelled') {
    return (label: 'Cancelled', action: null);
  }
  if (phase == 'ended') {
    return (label: 'Ended', action: null);
  }
  if (phase == 'live') {
    return (
      label: attending ? "You're registered · started" : 'Started',
      action: null,
    );
  }
  if (full) {
    return (label: 'Full', action: null);
  }
  return (
    label: attending ? "You're registered" : 'RSVPs closed',
    action: null,
  );
}
