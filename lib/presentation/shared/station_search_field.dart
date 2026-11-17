import 'package:flutter/material.dart';

import '../../domain/search/journey_search_service.dart';

class StationSearchField extends StatelessWidget {
  const StationSearchField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.icon,
    required this.stations,
    required this.onChanged,
    this.selection,
    this.suffixIcon,
  });

  final Key fieldKey;
  final String label;
  final IconData icon;
  final List<StationGroup> stations;
  final ValueChanged<StationGroup?> onChanged;
  final StationGroup? selection;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<StationGroup>(
      initialValue: TextEditingValue(text: selection?.displayLabel ?? ''),
      displayStringForOption: (station) => station.displayLabel,
      optionsBuilder: (value) => searchStations(stations, value.text),
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
            hintText: 'Search station or bus stop',
            prefixIcon: Icon(icon),
            suffixIcon: suffixIcon,
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }
}
