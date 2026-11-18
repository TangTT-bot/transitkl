import 'package:flutter/material.dart';

import '../../data/routing/routing_graph_repository.dart';
import 'appearance_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.feeds, this.appearance, super.key});

  final List<TransitFeedMetadata> feeds;
  final AppearanceController? appearance;

  @override
  Widget build(BuildContext context) {
    final dateFormat = MaterialLocalizations.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final style = Theme.of(context).textTheme.titleLarge;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (appearance case final controller?) ...[
              Text('Appearance', style: style),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (mode, label) in [
                      (ThemeMode.system, 'System'),
                      (ThemeMode.light, 'Light'),
                      (ThemeMode.dark, 'Dark'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: controller.mode == mode,
                        onSelected: controller.saving
                            ? null
                            : (selected) async {
                                if (!selected) return;
                                final saved = await controller.select(mode);
                                if (!saved && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not save appearance.',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text('Offline data', style: style),
            const SizedBox(height: 6),
            const Text(
              'Schedules are bundled with the app. Live delays and cancellations are not included.',
            ),
            for (final feed in feeds)
              Card(
                child: ListTile(
                  leading: Icon(
                    today.isAfter(feed.serviceDateEnd)
                        ? Icons.event_busy_outlined
                        : Icons.event_available_outlined,
                  ),
                  title: Text(feed.displayName),
                  subtitle: Text(
                    [
                      '${today.isAfter(feed.serviceDateEnd) ? 'Expired after' : 'Valid through'} ${dateFormat.formatFullDate(feed.serviceDateEnd)}',
                      'From ${dateFormat.formatFullDate(feed.serviceDateStart)}',
                      if (feed.id == 'prasarana_rapid_bus_kl' &&
                          feed.includedRouteCount != null)
                        '${feed.includedRouteCount} published routes · partial coverage',
                      if (feed.coverageNote.isNotEmpty) feed.coverageNote,
                    ].join('\n'),
                  ),
                ),
              ),
            const Text(
              'Exact departures are shown only where published. Other waits and walking times are estimates.',
            ),
            const SizedBox(height: 20),
            Text('About TransitKL', style: style),
            const SizedBox(height: 6),
            const Text(
              'An offline journey planner for Klang Valley. Favourites and appearance settings stay on this device.',
            ),
            const SizedBox(height: 8),
            const Text('Schedule source: data.gov.my · CC BY 4.0'),
          ],
        ),
      ),
    );
  }
}
