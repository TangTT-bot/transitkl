import 'package:flutter/material.dart';

import 'data/routing/routing_graph_repository.dart';
import 'presentation/journey_planner/journey_planner_screen.dart';

void main() {
  runApp(const TransitKlApp());
}

class TransitKlApp extends StatelessWidget {
  const TransitKlApp({super.key, this.repository});

  final RoutingGraphRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransitKL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A60)),
        useMaterial3: true,
      ),
      home: _TransitDataLoader(
        repository: repository ?? AssetRoutingGraphRepository(),
      ),
    );
  }
}

class _TransitDataLoader extends StatefulWidget {
  const _TransitDataLoader({required this.repository});

  final RoutingGraphRepository repository;

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
          return JourneyPlannerScreen(data: snapshot.requireData);
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
