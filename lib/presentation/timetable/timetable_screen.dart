import 'package:flutter/material.dart';

import '../../data/routing/routing_graph_repository.dart';
import '../../domain/search/journey_search_service.dart';
import '../../domain/timetable/station_timetable_service.dart';
import '../shared/station_search_field.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({
    required this.data,
    required this.stations,
    required this.initialDate,
    this.initialStation,
    super.key,
  });

  final TransitDataBundle data;
  final List<StationGroup> stations;
  final DateTime initialDate;
  final StationGroup? initialStation;

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  late final _service = StationTimetableService(widget.data.graph);
  late DateTime _date;
  StationGroup? _station;
  StationTimetable? _timetable;

  @override
  void initState() {
    super.initState();
    _date = DateUtils.dateOnly(widget.initialDate);
    _station = widget.initialStation;
    _readTimetable();
  }

  void _readTimetable() {
    final station = _station;
    _timetable = station == null
        ? null
        : _service.forStops(station.stopIds, _date);
  }

  Future<void> _chooseDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.data.feed.serviceDateStart,
      lastDate: widget.data.feed.serviceDateEnd,
      helpText: 'Select timetable date',
    );
    if (date == null || !mounted) return;
    setState(() {
      _date = date;
      _readTimetable();
    });
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    final station = _station;
    final localizations = MaterialLocalizations.of(context);
    final operators = station?.stopIds.map((id) => id.split(':').first).toSet();
    final feeds = widget.data.sources.where(
      (feed) => operators?.contains(feed.id) ?? false,
    );
    final departures = _group(
      timetable?.departures ?? [],
      (row) => row.service,
    );
    final frequencies = _group(
      timetable?.frequencies ?? [],
      (row) => row.service,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Timetables')),
      body: SafeArea(
        child: ListView(
          key: const Key('timetable-list'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'Offline schedules · Malaysia time (MYT)\n'
              'Live delays, cancellations and special service changes are not included.',
            ),
            const SizedBox(height: 16),
            StationSearchField(
              fieldKey: const Key('timetable-station-field'),
              label: 'Station or stop',
              icon: Icons.place_outlined,
              stations: widget.stations,
              selection: station,
              onChanged: (value) => setState(() {
                _station = value;
                _readTimetable();
              }),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('timetable-date-button'),
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(localizations.formatFullDate(_date)),
            ),
            const SizedBox(height: 12),
            if (station == null)
              const Text('Choose a station or bus stop from the suggestions.')
            else ...[
              for (final feed in feeds) ...[
                Text(
                  '${feed.displayName} · '
                  '${_date.isAfter(feed.serviceDateEnd) ? 'bundled timetable expired' : 'bundled timetable valid'} '
                  'through ${localizations.formatMediumDate(feed.serviceDateEnd)}',
                ),
                if (_date.isBefore(feed.serviceDateStart))
                  Text(
                    'Selected date is before the bundled timetable starts '
                    '(${localizations.formatMediumDate(feed.serviceDateStart)}).',
                  ),
              ],
              if (operators!.contains('prasarana_rapid_bus_kl'))
                const Text('Only bus routes in the bundled feed are shown.'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context, station),
                  icon: const Icon(Icons.trip_origin),
                  label: const Text('Use as From'),
                ),
              ),
              if (departures.isEmpty && frequencies.isEmpty)
                const Text(
                  'No departures or frequency windows in the bundled data for this date.',
                ),
              if (departures.isNotEmpty) ...[
                const _SectionTitle(
                  title: 'Scheduled departures',
                  description:
                      'Times are listed by direction. Check where shorter trips end.',
                ),
                for (final group in departures)
                  _ServiceCard(
                    service: group.key,
                    directionFirst: true,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final row in group.value)
                          Chip(
                            label: Text(
                              _clock(row.seconds, exact: true) +
                                  (row.endsAt == null
                                      ? ''
                                      : ' · Ends at ${row.endsAt}'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              if (frequencies.isNotEmpty) ...[
                const _SectionTitle(
                  title: 'Service frequency',
                  description:
                      'Approximate intervals, not exact departures. Route variants may overlap.',
                ),
                for (final group in frequencies)
                  _ServiceCard(
                    service: group.key,
                    note: group.value.any((row) => row.lineLevel)
                        ? 'Line-level windows; not station-specific first or last trains.'
                        : 'Estimated windows at this stop.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final row in group.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${_clock(row.startSeconds)}–${_clock(row.endSeconds)}'
                              ' · about every ${_interval(row.headwaySeconds)}',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(description),
      ],
    ),
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.child,
    this.note,
    this.directionFirst = false,
  });

  final TimetableDirection service;
  final Widget child;
  final String? note;
  final bool directionFirst;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            directionFirst ? service.direction : service.line,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(directionFirst ? service.line : service.direction),
          if (note case final note?) Text(note),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

List<MapEntry<TimetableDirection, List<T>>> _group<T>(
  List<T> rows,
  TimetableDirection Function(T) directionOf,
) {
  final groups = <TimetableDirection, List<T>>{};
  for (final row in rows) {
    (groups[directionOf(row)] ??= []).add(row);
  }
  return groups.entries.toList()..sort((a, b) {
    final line = a.key.line.compareTo(b.key.line);
    if (line != 0) return line;
    return a.key.direction.compareTo(b.key.direction);
  });
}

String _clock(int seconds, {bool exact = false}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hhmm = '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}';
  final remainder = seconds % 60;
  return exact && remainder != 0 ? '$hhmm:${two(remainder)}' : hhmm;
}

String _interval(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return [
    if (minutes > 0) '$minutes min',
    if (remainder > 0) '$remainder sec',
  ].join(' ');
}
