import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

const _rail = 'prasarana_rapid_rail:';

String _id(String code) => code.contains(':') ? code : '$_rail$code';

// Published interchange/connection points between bundled rail and BRT
// services. See docs/data-audits/rail-interchanges-2026-11-16.md for sources.
const _interchanges = {
  'Glenmarie': ['KJ27', 'SA7'],
  'Bandar Utama': ['KG09', 'SA1'],
  'Kwasa Damansara': ['KG04', 'PY01'],
  'Sungai Buloh': ['PY04', 'ktmb:18500'],
  'Sri Damansara Timur / Kepong Sentral': ['PY08', 'ktmb:18400'],
  'Kampung Batu': ['PY13', 'ktmb:50400'],
  'Titiwangsa': ['AG3', 'SP3', 'MR11', 'PY17'],
  'Ampang Park': ['KJ9', 'PY20'],
  'Tun Razak Exchange': ['KG20', 'PY23'],
  'Chan Sow Lin': ['AG11', 'SP11', 'PY24'],
  'Sungai Besi': ['SP16', 'PY29'],
  'KL Sentral / Muzium Negara': ['KJ15', 'MR1', 'KG15', 'ktmb:19100'],
  'Pasar Seni / Kuala Lumpur': ['KJ14', 'KG16', 'ktmb:19000'],
  'Merdeka / Plaza Rakyat': ['KG17', 'AG8', 'SP8'],
  'Bukit Bintang': ['KG18A', 'MR6'],
  'Maluri': ['KG22', 'AG13'],
  'Kajang': ['KG35', 'ktmb:20400'],
  'Masjid Jamek': ['KJ13', 'AG7', 'SP7'],
  'Hang Tuah': ['AG9', 'SP9', 'MR4'],
  'Putra Heights': ['KJ37', 'SP31'],
  'Subang Jaya': ['KJ28', 'ktmb:53700'],
  'Abdullah Hukum': ['KJ17', 'ktmb:52700'],
  'Bandar Tasik Selatan': ['SP15', 'ktmb:19600'],
  'USJ 7': ['KJ31', 'BRT7'],
  'Setia Jaya': ['BRT1', 'ktmb:53600'],
  'PWTC / Putra': ['AG4', 'SP4', 'ktmb:18800'],
  'Bandaraya / Bank Negara': ['AG6', 'SP6', 'ktmb:18900'],
  'Dang Wangi / Bukit Nanas': ['KJ12', 'MR8'],
  'Sultan Ismail / Medan Tuanku': ['AG5', 'SP5', 'MR9'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransitDataBundle data;
  late JourneySearchService search;

  setUpAll(() async {
    data = await AssetRoutingGraphRepository().load();
    search = JourneySearchService(data.graph);
  });

  test('the audited station pairs are boardable and linked both ways', () {
    final boardableIds = {
      for (final station in search.stations) ...station.stopIds,
    };
    final walkingLinks = {
      for (final edge in data.graph.transferEdges)
        (edge.fromStopId, edge.toStopId): edge,
    };
    for (final MapEntry(key: name, value: codes) in _interchanges.entries) {
      for (final from in codes) {
        expect(boardableIds, contains(_id(from)), reason: '$name: $from');
        for (final to in codes.where((code) => code != from)) {
          final link = walkingLinks[(_id(from), _id(to))];
          expect(
            link?.walkSeconds,
            greaterThan(0),
            reason: '$name: $from -> $to',
          );
        }
      }
    }
  });

  test('unverified namesakes and nearby stations are not joined', () {
    for (final (first, second) in [
      ('AG2', 'ktmb:50000'), // LRT and KTM Sentul are different stations.
      (
        'SP13',
        'ktmb:19400',
      ), // LRT and KTM Salak Selatan are not a marked link.
      (
        'SA20',
        'ktmb:54700',
      ), // Jambatan Kota is not a declared KTM interchange.
    ]) {
      expect(
        data.graph.transferEdges.any(
          (edge) =>
              (edge.fromStopId == _id(first) && edge.toStopId == _id(second)) ||
              (edge.fromStopId == _id(second) && edge.toStopId == _id(first)),
        ),
        isFalse,
      );
    }
  });

  Journey route(String from, String to) => search.search(
    origin: search.stations.singleWhere((station) => station.id == from),
    destination: search.stations.singleWhere((station) => station.id == to),
    departure: DateTime(2026, 11, 16, 8),
  )!;

  test('SS15 and Klang Jaya use Glenmarie with one transfer each way', () {
    for (final (from, to, linkFrom, linkTo) in [
      ('ss 15', 'klang jaya', 'KJ27', 'SA7'),
      ('klang jaya', 'ss 15', 'SA7', 'KJ27'),
    ]) {
      final journey = route(from, to);
      expect(journey.transferCount, 1);
      expect(journey.legs.whereType<TransitLeg>(), hasLength(2));
      final walk = journey.legs.whereType<WalkingLeg>().single;
      expect((walk.fromStopId, walk.toStopId), (_id(linkFrom), _id(linkTo)));
      expect(walk.walkSeconds, 480);
      // The reproduced detour took two hours. Leave room for some timetable
      // variation without allowing the Pasar Seni/Bandar Utama loop back in.
      expect(journey.totalTravelSeconds, lessThan(75 * 60));
    }
  });

  test('Pudu and Muzium Negara use Plaza Rakyat/Merdeka each way', () {
    for (final (from, to) in [
      ('pudu', 'muzium negara'),
      ('muzium negara', 'pudu'),
    ]) {
      final journey = route(from, to);
      expect(journey.transferCount, 1);
      final walk = journey.legs.whereType<WalkingLeg>().single;
      final endpoints = {walk.fromStopId, walk.toStopId};
      expect(endpoints, contains(_id('KG17')));
      expect(endpoints.intersection({_id('AG8'), _id('SP8')}), hasLength(1));
    }
  });
}
