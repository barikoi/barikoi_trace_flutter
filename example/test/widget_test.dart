// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:barikoi_trace_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test demo app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const TraceDemoApp());
    expect(find.text('Barikoi Trace'), findsOneWidget);
  });
}
