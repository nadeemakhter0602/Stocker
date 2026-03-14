import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const StockerApp());
    expect(find.byType(StockerApp), findsOneWidget);
  });
}
