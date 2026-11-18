import 'dart:async';

import 'package:flutter/material.dart';

import 'data/favourites/shared_preferences_favourites_repository.dart';
import 'data/routing/routing_graph_repository.dart';
import 'domain/favourites/favourites.dart';
import 'presentation/journey_planner/journey_planner_screen.dart';
import 'presentation/settings/appearance_controller.dart';

void main() {
  runApp(const TransitKlApp());
}

class TransitKlApp extends StatefulWidget {
  const TransitKlApp({
    super.key,
    this.repository,
    this.favouritesRepository,
    this.appearanceStore,
  });

  final RoutingGraphRepository? repository;
  final FavouritesRepository? favouritesRepository;
  final AppearanceStore? appearanceStore;

  @override
  State<TransitKlApp> createState() => _TransitKlAppState();
}

class _TransitKlAppState extends State<TransitKlApp> {
  late final _appearance = AppearanceController(
    widget.appearanceStore ?? LocalAppearanceStore(),
  );
  late final _repository = widget.repository ?? AssetRoutingGraphRepository();
  late final _favourites =
      widget.favouritesRepository ?? SharedPreferencesFavouritesRepository();

  @override
  void initState() {
    super.initState();
    unawaited(_appearance.load());
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF006A60),
      brightness: brightness,
    ),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appearance,
      child: _TransitDataLoader(
        repository: _repository,
        favouritesRepository: _favourites,
        appearance: _appearance,
      ),
      builder: (context, home) => MaterialApp(
        title: 'TransitKL',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: _appearance.mode,
        home: home,
      ),
    );
  }
}

class _TransitDataLoader extends StatefulWidget {
  const _TransitDataLoader({
    required this.repository,
    required this.favouritesRepository,
    required this.appearance,
  });

  final RoutingGraphRepository repository;
  final FavouritesRepository favouritesRepository;
  final AppearanceController appearance;

  @override
  State<_TransitDataLoader> createState() => _TransitDataLoaderState();
}

class _TransitDataLoaderState extends State<_TransitDataLoader> {
  late Future<TransitDataBundle> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.repository.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TransitDataBundle>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return JourneyPlannerScreen(
            data: snapshot.requireData,
            favouritesRepository: widget.favouritesRepository,
            appearance: widget.appearance,
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('TransitKL')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 52,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Transit data could not be loaded.',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The bundled routing file may be missing or invalid.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        _loadFuture = widget.repository.load();
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
