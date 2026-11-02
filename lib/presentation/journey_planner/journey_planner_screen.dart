import 'package:flutter/material.dart';

import '../../data/routing/routing_graph_repository.dart';
import '../../domain/routing/journey_planner.dart';
import '../../domain/routing/routing_graph.dart';
import '../../domain/search/journey_search_service.dart';

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({
    required this.data,
    this.initialDeparture,
    super.key,
  });

  final TransitDataBundle data;
  final DateTime? initialDeparture;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  late final JourneySearchService _searchService;
  late DateTime _departure;
  StationGroup? _origin;
  StationGroup? _destination;
  Journey? _journey;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _searchService = JourneySearchService(widget.data.graph);
    _departure = _initialDeparture(
      widget.data.feed,
      widget.initialDeparture ?? DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TransitKL'),
        actions: [
          IconButton(
            tooltip: 'About this data',
            onPressed: _showDataInformation,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Plan your journey',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Rapid Rail routes work fully offline.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _FeedStatusCard(feed: widget.data.feed),
            const SizedBox(height: 20),
            _StationField(
              fieldKey: const Key('origin-station-field'),
              label: 'From',
              icon: Icons.trip_origin,
              stations: _searchService.stations,
              onChanged: (station) => setState(() {
                _origin = station;
                _clearResult();
              }),
            ),
            const SizedBox(height: 12),
            _StationField(
              fieldKey: const Key('destination-station-field'),
              label: 'To',
              icon: Icons.location_on_outlined,
              stations: _searchService.stations,
              onChanged: (station) => setState(() {
                _destination = station;
                _clearResult();
              }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('departure-date-button'),
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_formatDate(_departure)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('departure-time-button'),
                    onPressed: _selectTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(_formatTime(_departure)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('find-journey-button'),
              onPressed: _origin != null && _destination != null
                  ? _findJourney
                  : null,
              icon: const Icon(Icons.route),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Find journey'),
              ),
            ),
            const SizedBox(height: 24),
            if (_journey case final journey?)
              JourneyResultView(graph: widget.data.graph, journey: journey)
            else if (_searched)
              const _NoJourneyCard(),
          ],
        ),
      ),
    );
  }

  void _clearResult() {
    _journey = null;
    _searched = false;
  }

  void _findJourney() {
    final origin = _origin!;
    final destination = _destination!;
    if (origin == destination) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose two different stations.')),
      );
      return;
    }
    setState(() {
      _journey = _searchService.search(
        origin: origin,
        destination: destination,
        departure: _departure,
      );
      _searched = true;
    });
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(_departure),
      firstDate: widget.data.feed.serviceDateStart,
      lastDate: widget.data.feed.serviceDateEnd,
      helpText: 'Select departure date',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _departure = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _departure.hour,
        _departure.minute,
      );
      _clearResult();
    });
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
      helpText: 'Select departure time',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _departure = DateTime(
        _departure.year,
        _departure.month,
        _departure.day,
        selected.hour,
        selected.minute,
      );
      _clearResult();
    });
  }

  void _showDataInformation() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline transit data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'This build contains static Rapid Rail GTFS data. Times are '
              'estimates based on published headways, not live arrivals.',
            ),
            const SizedBox(height: 8),
            const Text('Source: data.gov.my • CC BY 4.0'),
            const SizedBox(height: 8),
            Text(
              'Valid ${_formatDate(widget.data.feed.serviceDateStart)} to '
              '${_formatDate(widget.data.feed.serviceDateEnd)}.',
            ),
          ],
        ),
      ),
    );
  }
}

class JourneyResultView extends StatelessWidget {
  const JourneyResultView({
    required this.graph,
    required this.journey,
    super.key,
  });

  final RoutingGraph graph;
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('journey-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommended journey',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDuration(journey.totalTravelSeconds),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${journey.transferCount} transfer${journey.transferCount == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Arrive'),
                    Text(
                      _formatTime(journey.arrival),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final (index, leg) in journey.legs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _JourneyLegCard(graph: graph, leg: leg, number: index + 1),
          ),
      ],
    );
  }
}

class _StationField extends StatelessWidget {
  const _StationField({
    required this.fieldKey,
    required this.label,
    required this.icon,
    required this.stations,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final IconData icon;
  final List<StationGroup> stations;
  final ValueChanged<StationGroup?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<StationGroup>(
      displayStringForOption: (station) => station.name,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<StationGroup>.empty();
        return stations
            .where((station) => station.name.toLowerCase().contains(query))
            .take(12);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSubmitted(),
          onChanged: (_) => onChanged(null),
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Search station',
            prefixIcon: Icon(icon),
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }
}

class _FeedStatusCard extends StatelessWidget {
  const _FeedStatusCard({required this.feed});

  final TransitFeedMetadata feed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.offline_bolt_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Offline data • Rapid Rail • valid until '
                '${_formatDate(feed.serviceDateEnd)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyLegCard extends StatelessWidget {
  const _JourneyLegCard({
    required this.graph,
    required this.leg,
    required this.number,
  });

  final RoutingGraph graph;
  final JourneyLeg leg;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: switch (leg) {
          TransitLeg() => _transitContent(context, leg as TransitLeg),
          WalkingLeg() => _walkingContent(context, leg as WalkingLeg),
        },
      ),
    );
  }

  Widget _transitContent(BuildContext context, TransitLeg transit) {
    final service = graph.services[transit.serviceId]!;
    final from = _stopName(graph, transit.fromStopId);
    final to = _stopName(graph, transit.toStopId);
    final color = _routeColor(
      service.color,
      Theme.of(context).colorScheme.primary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: color,
          foregroundColor: _readableTextColor(color),
          child: Text(
            service.shortName.isEmpty ? '$number' : service.shortName,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$from → $to',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(service.longName),
              const SizedBox(height: 4),
              Text(
                '${transit.isScheduled ? 'Wait' : 'Average wait'} '
                '${_formatDuration(transit.waitSeconds)} • '
                'Ride ${_formatDuration(transit.rideSeconds)} • '
                '${transit.stopIds.length - 1} stops',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _walkingContent(BuildContext context, WalkingLeg walking) {
    final station = _stopName(graph, walking.fromStopId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(child: Icon(Icons.directions_walk)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transfer at $station',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Walk ${_formatDuration(walking.walkSeconds)}'
                '${walking.distanceMetres == null ? '' : ' • ${walking.distanceMetres} m'}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoJourneyCard extends StatelessWidget {
  const _NoJourneyCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              Icons.route_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No journey was found within six hours. Try another date, '
                'time, or station.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DateTime _initialDeparture(TransitFeedMetadata feed, DateTime now) {
  final today = DateUtils.dateOnly(now);
  final date = today.isBefore(feed.serviceDateStart)
      ? feed.serviceDateStart
      : today.isAfter(feed.serviceDateEnd)
      ? feed.serviceDateEnd
      : today;
  return DateTime(date.year, date.month, date.day, now.hour, now.minute);
}

String _stopName(RoutingGraph graph, String stopId) =>
    _titleCase(graph.stops[stopId]!.name);

String _titleCase(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .map((word) {
      if (word.isEmpty) return word;
      if (word.length <= 5 &&
          word == word.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(word)) {
        return word;
      }
      final lower = word.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    })
    .join(' ');

String _formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _formatTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatDuration(int seconds) {
  if (seconds == 0) return '0 min';
  final roundedMinutes = (seconds / Duration.secondsPerMinute).ceil();
  final hours = roundedMinutes ~/ 60;
  final minutes = roundedMinutes % 60;
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours hr';
  return '$hours hr $minutes min';
}

Color _routeColor(String? hex, Color fallback) {
  if (hex == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return fallback;
  }
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

Color _readableTextColor(Color background) =>
    background.computeLuminance() > 0.45 ? Colors.black : Colors.white;
