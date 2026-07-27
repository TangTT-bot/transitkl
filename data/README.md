# Transit data workspace

- `fixtures/` contains small synthetic feeds used by automated tests.
- `downloads/` contains official GTFS ZIP downloads and is ignored by Git.
- `processed/` contains generated audit JSON and SQLite databases and is
  ignored by Git.

Production files in `downloads/` and `processed/` can always be recreated with
the commands documented in the repository README.

