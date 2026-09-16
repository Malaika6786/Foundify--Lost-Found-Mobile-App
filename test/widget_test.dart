// Basic smoke test: the app boots to the onboarding screen when signed out.
import 'package:flutter_test/flutter_test.dart';

import 'package:lost_and_found_app/main.dart';

void main() {
  testWidgets('App boots to onboarding when signed out', (WidgetTester tester) async {
    await tester.pumpWidget(const LostFoundApp());
    await tester.pump();

    expect(find.text('Get Started'), findsOneWidget);
  });
}
