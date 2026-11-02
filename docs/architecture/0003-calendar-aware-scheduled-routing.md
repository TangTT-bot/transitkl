# ADR 0003: Combine frequency and exact scheduled routing

## Status

Accepted.

## Context

Rapid Rail publishes frequency windows, where half the headway is a reasonable
expected wait. KTM Komuter and many bus feeds publish exact departures instead.
Treating those services as frequencies can invent trains that do not exist.
Ignoring GTFS calendars can also offer weekday service on weekends or removed
service on a public holiday.

## Decision

Routing graph version 2 includes:

- base Monday-to-Sunday service calendars and their validity dates;
- `calendar_dates.txt` additions and removals;
- a calendar identifier on every frequency window; and
- full stop times for trips without a `frequencies.txt` entry.

Journey searches receive a local departure `DateTime`. Frequency boarding is
allowed only when its headway window and calendar are active. Exact trips use
their published departure and arrival times, including dwell time while a rider
stays aboard. GTFS times above 24:00 are evaluated against the previous service
day, so a Monday `24:30` train is correctly found at 00:30 on Tuesday.

The Dijkstra state now records the stop, last used service, and active vehicle
run. Walking clears the active run but preserves the last service for transfer
costing. An exact trip instance contains its GTFS trip ID, service date, and
current stop index, preventing the router from jumping between different train
runs. Searches use a configurable six-hour default horizon to avoid returning
a next-day departure as a useful journey.

## Consequences

- Frequency and timetable services can participate in the same journey.
- Calendar exceptions override the base weekly calendar.
- Actual arrival times remain separate from the generalized transfer penalty.
- Schedule-only routes are no longer given a fabricated fallback headway.
- The mobile application must supply a departure date and time for every search.

The next milestone is loading the generated routing data through a Flutter
repository and building stop-search and journey-results screens. Real-time
delays and cancellations remain outside the capstone MVP.
