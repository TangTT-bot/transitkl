# ADR 0004: Bundle the validated routing graph behind a repository

## Status

Accepted for the first application vertical slice.

## Context

The preprocessing pipeline already produces both a normalized SQLite database
and a compact JSON graph. The routing engine needs the graph in memory, and the
current Rapid Rail export is small enough to bundle directly. Introducing a
mobile SQLite plugin before validating the user journey flow would add platform
setup without changing the routing result.

## Decision

The Flutter application bundles the audited routing graph as an asset and loads
it through `RoutingGraphRepository`. The repository validates feed metadata and
graph schema before exposing the domain model. Screens depend on the loaded
bundle, not on Flutter asset APIs or raw JSON.

Station search groups stops by normalized name because the Rapid Rail feed
models interchange platforms as separate stop IDs. Journey search evaluates
every platform combination and selects the lowest generalized-cost result.

The generated SQLite database remains the normalized preprocessing artifact.
If runtime SQLite becomes necessary for larger merged feeds or is mandatory in
the final project specification, a SQLite repository can replace the asset
repository without changing the search screen or routing engine.

## Consequences

- The first app feature works fully offline with no additional packages.
- Automated widget tests can execute the same graph and router as the app.
- Feed validity and static-data limitations can be shown before a search.
- An audited graph must be deliberately copied into `assets/data` after a feed
  refresh; ignored pipeline output is never bundled accidentally.
- The complete graph is parsed at startup. Memory and startup performance must
  be measured again after KTM and Rapid Bus data are merged.
