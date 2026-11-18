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
import '../settings/appearance_controller.dart';
import '../settings/settings_screen.dart';
import '../shared/station_search_field.dart';
import '../timetable/timetable_screen.dart';

enum _HomeTab { plan, timetables, saved }

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({
    required this.data,
    this.initialDeparture,
    this.searchRunner = runJourneySearch,
    this.favouritesRepository,
    this.appearance,
    super.key,
  });

  final TransitDataBundle data;
  final DateTime? initialDeparture;
  final JourneySearchRunner searchRunner;
  final FavouritesRepository? favouritesRepository;
  final AppearanceController? appearance;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  late final JourneySearchService _searchService;
  FavouritesController? _favourites;
  _HomeTab _tab = _HomeTab.plan;
  bool _timetableOpened = false;
  int _timetableVersion = 0;
  StationGroup? _timetableStation;
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
    final colours = Theme.of(context).colorScheme;
    final favourites = _favourites;
    return PopScope(
      canPop: _tab == _HomeTab.plan,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != _HomeTab.plan) _selectTab(_HomeTab.plan);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            _HomeTab.plan => 'TransitKL',
            _HomeTab.timetables => 'Timetables',
            _HomeTab.saved => 'Saved',
          }),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab.index,
            sizing: StackFit.expand,
            children: [
              _tabContent(_HomeTab.plan, _buildPlan(context)),
              _tabContent(
                _HomeTab.timetables,
                _timetableOpened
                    ? TimetableScreen(
                        key: ValueKey(_timetableVersion),
                        data: widget.data,
                        stations: _searchService.stations,
                        initialDate: _departure,
                        initialStation: _timetableStation ?? _origin,
                        onUseAsFrom: (station) => _applySavedSelection((
                          origin: station,
                          destination: null,
                        )),
                      )
                    : const SizedBox.shrink(),
              ),
              _tabContent(
                _HomeTab.saved,
                favourites != null
                    ? FavouritesScreen(
                        controller: favourites,
                        onUse: _applySavedSelection,
                        onTimetable: _viewTimetable,
                      )
                    : const Center(
                        child: Text('Saved journeys are unavailable.'),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : NavigationBar(
                selectedIndex: _tab.index,
                indicatorColor: colours.secondaryContainer,
                onDestinationSelected: (index) =>
                    _selectTab(_HomeTab.values[index]),
                destinations: const [
                  NavigationDestination(
                    key: Key('plan-tab'),
                    icon: Icon(Icons.route_outlined),
                    selectedIcon: Icon(Icons.route),
                    label: 'Plan',
                  ),
                  NavigationDestination(
                    key: Key('timetables-tab'),
                    icon: Icon(Icons.schedule_outlined),
                    selectedIcon: Icon(Icons.schedule),
                    label: 'Timetables',
                  ),
                  NavigationDestination(
                    key: Key('saved-tab'),
                    icon: Icon(Icons.bookmark_outline),
                    selectedIcon: Icon(Icons.bookmark),
                    label: 'Saved',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tabContent(_HomeTab tab, Widget child) => ExcludeFocus(
    excluding: _tab != tab,
    child: TickerMode(enabled: _tab == tab, child: child),
  );

  Widget _buildPlan(BuildContext context) {
    final favourites = _favourites;
    final origin = _origin;
    final destination = _destination;
    final hasBus = widget.data.sources.any(
      (feed) => feed.id == 'prasarana_rapid_bus_kl',
    );
    final unavailable = widget.data.sources.where(
      (feed) =>
          DateUtils.dateOnly(_departure).isAfter(feed.serviceDateEnd) ||
          DateUtils.dateOnly(_departure).isBefore(feed.serviceDateStart),
    );
    return ListView(
      key: const PageStorageKey('plan-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Plan your journey',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Swap From and To',
              onPressed: origin != null && destination != null
                  ? _swapStations
                  : null,
              icon: const Icon(Icons.swap_vert),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
          suffixIcon: _stationFavouriteButton(favourites, destination, 'To'),
          onChanged: (station) => setState(() {
            _destination = station;
            _clearResult();
          }),
        ),
        const SizedBox(height: 12),
        const Text('Departure · Malaysia time'),
        const SizedBox(height: 4),
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
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Bundled schedules do not cover this departure date for '
            '${unavailable.map((feed) => feed.displayName).join(' and ')}.',
            key: const Key('plan-data-warning'),
          ),
        ],
        if (hasBus) ...[
          const SizedBox(height: 8),
          Text(
            'Offline schedules · Partial bus coverage',
            key: const Key('bus-coverage-notice'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        if (_searchError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_searchError!, key: const Key('journey-search-error')),
                  TextButton(
                    onPressed: _searching ? null : _findJourney,
                    child: const Text('Retry search'),
                  ),
                ],
              ),
            ),
          )
        else if (_journey case final journey?)
          JourneyResultView(
            graph: widget.data.graph,
            journey: journey,
            onViewTimetable: (stopId) {
              final station = _searchService.stations.firstWhere(
                (station) => station.stopIds.contains(stopId),
              );
              _viewTimetable(station);
            },
          )
        else if (_searched)
          _NoJourneyCard(onChangeDeparture: _selectTime),
      ],
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

  void _selectTab(_HomeTab tab) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = tab;
      if (tab == _HomeTab.timetables) _timetableOpened = true;
    });
  }

  void _viewTimetable(StationGroup station) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _timetableStation = station;
      _timetableVersion++;
      _timetableOpened = true;
      _tab = _HomeTab.timetables;
    });
  }

  void _swapStations() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final previousOrigin = _origin;
      _origin = _destination;
      _destination = previousOrigin;
      _originFieldVersion++;
      _destinationFieldVersion++;
      _clearResult();
    });
  }

  void _applySavedSelection(FavouriteSelection selection) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = _HomeTab.plan;
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

  void _openSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          feeds: widget.data.sources,
          appearance: widget.appearance,
        ),
      ),
    );
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
}

class JourneyResultView extends StatelessWidget {
  const JourneyResultView({
    required this.graph,
    required this.journey,
    this.onViewTimetable,
    super.key,
  });

  final RoutingGraph graph;
  final Journey journey;
  final ValueChanged<String>? onViewTimetable;

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
                onViewTimetable: onViewTimetable == null
                    ? null
                    : () => onViewTimetable!(timing.leg.fromStopId),
              ),
            ),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Arrive ${_formatJourneyTime(journey.arrival, journey.departure)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text(_formatDuration(journey.totalTravelSeconds)),
                    Text(
                      '${journey.transferCount} transfer${journey.transferCount == 1 ? '' : 's'}',
                    ),
                    Text(
                      'Walking ${_formatDuration(journey.totalWalkingSeconds)}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Total from ${_formatTime(journey.departure)}'),
                Text(
                  'Waiting (included): ${_formatDuration(journey.totalWaitingSeconds)}',
                ),
                Text(
                  'Riding + walking: ${_formatDuration(journey.totalMovingSeconds)}',
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
    this.onViewTimetable,
  });

  final RoutingGraph graph;
  final JourneyLegTiming timing;
  final DateTime journeyDate;
  final VoidCallback? onViewTimetable;

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
            if (onViewTimetable != null)
              TextButton(
                onPressed: onViewTimetable,
                child: const Text('View boarding timetable'),
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
  const _NoJourneyCard({required this.onChangeDeparture});

  final VoidCallback onChangeDeparture;

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No journey was found within six hours. Try another time, date, or stop.',
                  ),
                  TextButton(
                    onPressed: onChangeDeparture,
                    child: const Text('Change departure time'),
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
