import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/routing/journey_search_executor.dart';
import '../../data/routing/routing_graph_repository.dart';
import '../../domain/favourites/favourites.dart';
import '../../domain/routing/journey_planner.dart';
import '../../domain/routing/routing_graph.dart';
import '../../domain/search/journey_search_service.dart';
import '../favourites/favourites_controller.dart';
import '../favourites/favourites_screen.dart';
import '../shared/station_search_field.dart';
import '../timetable/timetable_screen.dart';

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({
    required this.data,
    this.initialDeparture,
    this.searchRunner = runJourneySearch,
    this.favouritesRepository,
    super.key,
  });

  final TransitDataBundle data;
  final DateTime? initialDeparture;
  final JourneySearchRunner searchRunner;
  final FavouritesRepository? favouritesRepository;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  late final JourneySearchService _searchService;
  FavouritesController? _favourites;
  int _originFieldVersion = 0;
  int _destinationFieldVersion = 0;
  late DateTime _departure;
  StationGroup? _origin;
  StationGroup? _destination;
  Journey? _journey;
  bool _searched = false;
  bool _searching = false;
  String? _searchError;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _searchService = JourneySearchService(widget.data.graph);
    if (widget.favouritesRepository case final repository?) {
      final controller = FavouritesController(
        repository,
        _searchService.stations,
      );
      _favourites = controller;
      unawaited(controller.load());
      controller.addListener(_refreshFavourites);
    }
    _departure = _initialDeparture(
      widget.data.feed,
      widget.initialDeparture ?? DateTime.now(),
    );
  }

  void _refreshFavourites() => setState(() {});

  @override
  void dispose() {
    _favourites?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favourites = _favourites;
    final origin = _origin;
    final destination = _destination;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TransitKL'),
        actions: [
          IconButton(
            tooltip: 'Timetables',
            onPressed: _openTimetable,
            icon: const Icon(Icons.schedule),
          ),
          if (favourites != null)
            IconButton(
              tooltip: 'Favourites',
              onPressed: () => _openFavourites(favourites),
              icon: const Icon(Icons.star_outline),
            ),
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
              'Rail, KTM Komuter, Sunway BRT and published Rapid Bus routes, offline.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _FeedStatusCard(feeds: widget.data.sources),
            if (widget.data.sources.any(
              (feed) => feed.id == 'prasarana_rapid_bus_kl',
            )) ...[
              const SizedBox(height: 8),
              const Text(
                'Partial bus coverage: only officially published routes and usable trips. '
                'Not all Klang Valley buses or rail/bus connections are included.',
                key: Key('bus-coverage-notice'),
              ),
            ],
            const SizedBox(height: 20),
            StationSearchField(
              key: ValueKey(('from', _originFieldVersion)),
              fieldKey: const Key('origin-station-field'),
              label: 'From',
              icon: Icons.trip_origin,
              stations: _searchService.stations,
              selection: origin,
              suffixIcon: _stationFavouriteButton(favourites, origin, 'From'),
              onChanged: (station) => setState(() {
                _origin = station;
                _clearResult();
              }),
            ),
            const SizedBox(height: 12),
            StationSearchField(
              key: ValueKey(('to', _destinationFieldVersion)),
              fieldKey: const Key('destination-station-field'),
              label: 'To',
              icon: Icons.location_on_outlined,
              stations: _searchService.stations,
              selection: destination,
              suffixIcon: _stationFavouriteButton(
                favourites,
                destination,
                'To',
              ),
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
              onPressed: !_searching && _origin != null && _destination != null
                  ? _findJourney
                  : null,
              icon: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.route),
              label: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(_searching ? 'Finding journey...' : 'Find journey'),
              ),
            ),
            if (favourites != null &&
                origin != null &&
                destination != null &&
                origin != destination)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: favourites.canEdit
                      ? () => _saveFavourite(
                          favourites.toggleJourney(origin, destination),
                        )
                      : null,
                  icon: Icon(
                    favourites.hasJourney(origin, destination)
                        ? Icons.star
                        : Icons.star_outline,
                  ),
                  label: Text(
                    favourites.hasJourney(origin, destination)
                        ? 'Remove saved journey'
                        : 'Save journey',
                  ),
                ),
              ),
            const SizedBox(height: 24),
            if (_searchError != null)
              Text(_searchError!, key: const Key('journey-search-error'))
            else if (_journey case final journey?)
              JourneyResultView(graph: widget.data.graph, journey: journey)
            else if (_searched)
              const _NoJourneyCard(),
          ],
        ),
      ),
    );
  }

  Widget? _stationFavouriteButton(
    FavouritesController? favourites,
    StationGroup? station,
    String field,
  ) {
    if (favourites == null || station == null) return null;
    final saved = favourites.hasStation(station);
    return IconButton(
      tooltip: saved
          ? 'Remove $field stop from favourites'
          : 'Save $field stop',
      icon: Icon(saved ? Icons.star : Icons.star_outline),
      onPressed: favourites.canEdit
          ? () => _saveFavourite(favourites.toggleStation(station))
          : null,
    );
  }

  Future<void> _saveFavourite(Future<bool> result) async {
    if (await result || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not update favourites. Try again.')),
    );
  }

  Future<void> _openTimetable() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final station = await Navigator.of(context).push<StationGroup>(
      MaterialPageRoute(
        builder: (context) => TimetableScreen(
          data: widget.data,
          stations: _searchService.stations,
          initialDate: _departure,
          initialStation: _origin,
        ),
      ),
    );
    if (!mounted || station == null) return;
    setState(() {
      _origin = station;
      _originFieldVersion++;
      _clearResult();
    });
  }

  Future<void> _openFavourites(FavouritesController favourites) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selection = await Navigator.of(context).push<FavouriteSelection>(
      MaterialPageRoute(
        builder: (context) => FavouritesScreen(controller: favourites),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      if (selection.origin case final origin?) {
        _origin = origin;
        _originFieldVersion++;
      }
      if (selection.destination case final destination?) {
        _destination = destination;
        _destinationFieldVersion++;
      }
      _clearResult();
    });
  }

  void _clearResult() {
    _journey = null;
    _searched = false;
    _searchError = null;
    _requestVersion++;
  }

  Future<void> _findJourney() async {
    if (_searching) return;
    final origin = _origin!;
    final destination = _destination!;
    if (origin == destination) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose two different stations.')),
      );
      return;
    }
    final version = ++_requestVersion;
    setState(() {
      _searching = true;
      _journey = null;
      _searchError = null;
      _searched = false;
    });
    try {
      final result = await widget.searchRunner(
        JourneySearchRequest(
          graph: widget.data.graph,
          origin: origin,
          destination: destination,
          departure: _departure,
        ),
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _journey = result;
        _searched = true;
      });
    } on Object {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _searchError =
            'Journey search could not be completed. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
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
        child: SingleChildScrollView(
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
                'Rapid Rail, Sunway BRT and frequency-based buses use estimated waits from published headways. '
                'KTM Komuter uses exact scheduled departures. Walking allowances '
                'are estimates. Live delays and cancellations are not included.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Some Komuter trips terminate early. Results follow the supplied timetable, including service gaps.',
              ),
              for (final feed in widget.data.sources.where(
                (feed) => feed.coverageNote.isNotEmpty,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(feed.coverageNote),
                ),
              const SizedBox(height: 8),
              const Text('Source: data.gov.my • CC BY 4.0'),
              const SizedBox(height: 8),
              for (final feed in widget.data.sources)
                Text(
                  '${feed.displayName}: ${_formatDate(feed.serviceDateStart)} '
                  'to ${_formatDate(feed.serviceDateEnd)}.',
                ),
            ],
          ),
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
    final timedLegs = journey.timedLegs.toList();
    return Column(
      key: const Key('journey-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommended journey',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        for (final timing in timedLegs)
          if (timing.leg case TransitLeg(
            isScheduled: true,
            waitSeconds: >= Duration.secondsPerHour,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScheduledWaitNotice(
                graph: graph,
                timing: timing,
                journeyDate: journey.departure,
              ),
            ),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total from ${_formatTime(journey.departure)}'),
                      Text(
                        _formatDuration(journey.totalTravelSeconds),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Waiting (included): ${_formatDuration(journey.totalWaitingSeconds)}',
                      ),
                      Text(
                        'Riding + walking: ${_formatDuration(journey.totalMovingSeconds)}',
                      ),
                      Text(
                        '${journey.transferCount} transfer${journey.transferCount == 1 ? '' : 's'}',
                      ),
                      Text(
                        'Walking ${_formatDuration(journey.totalWalkingSeconds)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Arrive'),
                      Text(
                        _formatJourneyTime(journey.arrival, journey.departure),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final (index, timing) in timedLegs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _JourneyLegCard(
              graph: graph,
              timing: timing,
              number: index + 1,
              journeyDate: journey.departure,
            ),
          ),
      ],
    );
  }
}

class _ScheduledWaitNotice extends StatelessWidget {
  const _ScheduledWaitNotice({
    required this.graph,
    required this.timing,
    required this.journeyDate,
  });

  final RoutingGraph graph;
  final JourneyLegTiming timing;
  final DateTime journeyDate;

  @override
  Widget build(BuildContext context) {
    final leg = timing.leg as TransitLeg;
    final service = graph.services[leg.serviceId]!;
    final mode = service.id.startsWith('ktmb:')
        ? 'KTM Komuter'
        : service.shortName;
    final boarding = _formatJourneyTime(timing.boardsAt!, journeyDate);
    final stop = _stopName(graph, leg.fromStopId);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Long scheduled wait',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'The ${mode.isEmpty ? 'service' : mode} departure in this journey is scheduled for $boarding at $stop.',
            ),
            Text('Wait at this stop: ${_formatDuration(leg.waitSeconds)}.'),
            const Text('Try a later start time to reduce the wait.'),
          ],
        ),
      ),
    );
  }
}

class _FeedStatusCard extends StatelessWidget {
  const _FeedStatusCard({required this.feeds});

  final List<TransitFeedMetadata> feeds;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final feed in feeds)
                    Text(
                      '${feed.displayName} • '
                      '${feed.id == 'prasarana_rapid_bus_kl' ? '${feed.includedRouteCount} published routes • ' : ''}'
                      '${DateUtils.dateOnly(DateTime.now()).isAfter(feed.serviceDateEnd) ? 'expired' : 'valid until'} '
                      '${_formatDate(feed.serviceDateEnd)}',
                    ),
                ],
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
    required this.timing,
    required this.number,
    required this.journeyDate,
  });

  final RoutingGraph graph;
  final JourneyLegTiming timing;
  final int number;
  final DateTime journeyDate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: switch (timing.leg) {
          final TransitLeg leg => _transitContent(context, leg),
          final WalkingLeg leg => _walkingContent(context, leg),
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
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: FittedBox(
              child: Text(
                service.id.startsWith('ktmb:')
                    ? 'KTM'
                    : service.shortName.isEmpty
                    ? '$number'
                    : service.shortName,
              ),
            ),
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
              if (transit.isScheduled)
                Text(
                  'Scheduled boarding: ${_formatJourneyTime(timing.boardsAt!, journeyDate)}',
                ),
              Text(
                '${transit.isScheduled ? 'Wait' : 'Estimated wait'} '
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
                'time, or stop. Missing published data or an unconfigured walking '
                'connection can also prevent a result.',
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

String _formatJourneyTime(DateTime value, DateTime journeyDate) =>
    DateUtils.isSameDay(value, journeyDate)
    ? _formatTime(value)
    : '${_formatTime(value)} on ${_formatDate(value)}';

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
