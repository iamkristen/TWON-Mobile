import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models.dart';
import '../../core/env_config.dart';
import '../../shared/forms.dart';
import '../../shared/widgets.dart';
import '../auth/auth_cubit.dart';

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
                    if (event.text('image').isNotEmpty)
                      BrandImage(event.text('image'), width: double.infinity),
                    const SizedBox(height: 12),
                    Text(
                      event.text('title'),
                      style: Theme.of(c).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${dateLabel(event.text('date'))} · ${event.text('time')} UTC',
                    ),
                    Text(event.text('location')),
                    Text('${event.number('attendeeCount')} attending'),
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
      final ended =
          (DateTime.tryParse(
                    '${event.text('date').split('T').first}T${event.text('endTime', event.text('time'))}:00Z',
                  ) ??
                  DateTime.now())
              .isBefore(DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (event.text('image').isNotEmpty)
            BrandImage(event.text('image'), width: double.infinity),
          const SizedBox(height: 20),
          PageHeading(
            event.text('title'),
            '${dateLabel(event.text('date'))} · ${event.text('time')}${event.text('endTime').isNotEmpty ? '–${event.text('endTime')}' : ''} UTC',
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
          ActionButton(
            label: attending ? 'Cancel RSVP' : 'Join gathering',
            enabled: attending || !ended,
            action: () => repository(c).request(
              'events/$id/attend',
              method: attending ? 'DELETE' : 'POST',
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
                              final csv =
                                  'Name,Handle,Email\n${attendees.map((r) => [r['fullName'], r['handle'], r['email']].map((s) => '"${s?.toString().replaceAll('"', '""') ?? ''}"').join(',')).join('\n')}';
                              await SharePlus.instance.share(
                                ShareParams(
                                  text: csv,
                                  title: 'Gathering attendees',
                                ),
                              );
                            },
                          ),
                        ActionButton(
                          label: 'Delete gathering',
                          tonal: true,
                          confirmation: 'Remove this gathering for everyone?',
                          action: () => repository(
                            c,
                          ).request('events/$id', method: 'DELETE'),
                          onSuccess: (_) => c.pop(),
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
      FieldSpec(
        'date',
        'Date',
        kind: FieldKind.date,
        initial: initial?['date']?.toString().split('T').first,
      ),
      FieldSpec(
        'time',
        'Start time (UTC)',
        kind: FieldKind.time,
        initial: initial?['time'],
      ),
      FieldSpec(
        'endTime',
        'End time (UTC)',
        kind: FieldKind.time,
        required: false,
        initial: initial?['endTime'],
      ),
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
      if ('${v['endTime']}'.isNotEmpty &&
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
