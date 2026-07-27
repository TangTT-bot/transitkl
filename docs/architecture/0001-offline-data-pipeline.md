# ADR 0001: Prebuild the offline transit database

## Status

Accepted.

## Context

TransitKL must search stops, display timetables, and calculate journeys without
continuous network access. Parsing several raw GTFS CSV files during mobile app
startup would increase startup cost, duplicate validation logic in Dart, and
make data problems harder to reproduce.

## Decision

A Python tool will audit and transform versioned GTFS inputs into a normalized,
indexed SQLite database before the mobile application is built.

The application will use two databases:

1. A generated transit database, treated as read-only and replaceable.
2. A writable user database for favourites and preferences.

Feed identifiers are prepended to GTFS identifiers during import so records
from different operators cannot collide.

## Consequences

- Offline startup and queries are predictable.
- Feed problems are detected before an application release.
- Transit data can be refreshed without deleting user favourites.
- The preprocessing pipeline becomes part of the reproducible academic
  implementation and must be tested and documented.

