# TransitKL
TransitKL is an offline-first Flutter application that:
-Combines Rapid Rail, selected Rapid Bus services, and KTM Komuter information.
-Stores processed GTFS schedules locally in SQLite.
-Searches stations, stops, routes, and timetables without internet access.
-Generates cross-operator journey recommendations.
-Uses modified Dijkstra routing that considers travel, waiting, walking, and transfer inconvenience.
-Shows journey legs, estimated duration, transfers, and data limitations.
-Stores favourites locally without accounts or a backend.
The core academic contribution is not merely “a public transport app.” It is the combination of:
1. Multi-operator GTFS preprocessing.
2. An offline database architecture.
3. A transfer-aware routing model.
4. A usable mobile presentation of the result.
