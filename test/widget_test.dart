import 'package:flutter_test/flutter_test.dart';

import 'package:travel_plan/main.dart';

void main() {
  testWidgets('应用可启动', (WidgetTester tester) async {
    await tester.pumpWidget(const TravelPlanApp());
    await tester.pump();
    expect(find.textContaining('规划路线'), findsOneWidget);
  });
}
