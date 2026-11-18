import 'package:flutter/material.dart';

import '../../domain/search/journey_search_service.dart';
import 'favourites_controller.dart';

typedef FavouriteSelection = ({
  StationGroup? origin,
  StationGroup? destination,
});

class FavouritesScreen extends StatelessWidget {
  const FavouritesScreen({
    required this.controller,
    required this.onUse,
    required this.onTimetable,
    super.key,
  });

  final FavouritesController controller;
  final ValueChanged<FavouriteSelection> onUse;
  final ValueChanged<StationGroup> onTimetable;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (screenContext, child) {
        final snapshot = controller.snapshot;
        if (snapshot == null) {
          return Center(
            child: controller.loadFailed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load favourites on this device.'),
                      TextButton(
                        onPressed: controller.load,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Saving favourites',
              ),
            Text(
              'Journeys',
              style: Theme.of(screenContext).textTheme.titleLarge,
            ),
            if (snapshot.journeys.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Select From and To in the planner, then tap Save journey.',
                ),
              ),
            for (final saved in snapshot.journeys)
              Builder(
                builder: (context) {
                  final from = controller.resolve(saved.origin);
                  final to = controller.resolve(saved.destination);
                  final available = from != null && to != null && from != to;
                  return ListTile(
                    leading: const Icon(Icons.route_outlined),
                    title: Text(from?.displayLabel ?? saved.origin.label),
                    subtitle: Text(
                      'To ${to?.displayLabel ?? saved.destination.label}\n'
                      '${available ? 'Tap to fill From and To' : 'Unavailable in this network'}',
                    ),
                    onTap: available
                        ? () => onUse((origin: from, destination: to))
                        : null,
                    trailing: IconButton(
                      tooltip: 'Remove saved journey',
                      onPressed: controller.canEdit
                          ? () => _remove(
                              screenContext,
                              controller.removeJourney(saved),
                              () => controller.restoreJourney(saved),
                            )
                          : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            Text(
              'Stations and stops',
              style: Theme.of(screenContext).textTheme.titleLarge,
            ),
            if (snapshot.stations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Tap the star next to a selected station or stop in the planner.',
                ),
              ),
            for (final saved in snapshot.stations)
              Builder(
                builder: (context) {
                  final station = controller.resolve(saved);
                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(station?.displayLabel ?? saved.label),
                    subtitle: Text(
                      station == null
                          ? 'Unavailable in this network'
                          : 'Choose From or To',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (station != null)
                          PopupMenuButton<String>(
                            tooltip: 'Use saved station',
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'from',
                                child: Text('Use as From'),
                              ),
                              PopupMenuItem(
                                value: 'to',
                                child: Text('Use as To'),
                              ),
                              PopupMenuItem(
                                value: 'times',
                                child: Text('View timetable'),
                              ),
                            ],
                            onSelected: (action) {
                              if (action == 'times') {
                                onTimetable(station);
                              } else {
                                onUse((
                                  origin: action == 'from' ? station : null,
                                  destination: action == 'to' ? station : null,
                                ));
                              }
                            },
                          ),
                        IconButton(
                          tooltip: 'Remove saved station',
                          onPressed: controller.canEdit
                              ? () => _remove(
                                  screenContext,
                                  controller.removeStation(saved),
                                  () => controller.restoreStation(saved),
                                )
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _remove(
    BuildContext context,
    Future<bool> result,
    Future<bool> Function() restore,
  ) async {
    final removed = await result;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!removed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not update favourites. Try again.'),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from Saved'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (await restore() || !context.mounted) return;
            messenger.showSnackBar(
              const SnackBar(content: Text('Could not restore the favourite.')),
            );
          },
        ),
      ),
    );
  }
}
