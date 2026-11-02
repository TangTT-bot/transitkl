import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/main.dart';

void main() {
  testWidgets('shows the TransitKL project milestone', (tester) async {
    await tester.pumpWidget(const TransitKlApp());

    expect(find.text('TransitKL'), findsOneWidget);
    expect(
      find.text('Offline-first journey planning for Klang Valley'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Current milestone: calendar-aware frequency and scheduled routing.',
      ),
      findsOneWidget,
    );
  });
}
