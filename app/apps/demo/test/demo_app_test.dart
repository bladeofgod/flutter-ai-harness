import 'package:demo_app/demo_app.dart';
import 'package:demo_app/main.dart' as demo_entrypoint;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the neutral harness shell', (tester) async {
    await tester.pumpWidget(const DemoApp());

    expect(find.text('Flutter AI Harness'), findsOneWidget);
  });

  testWidgets('main reuses the Flutter test binding', (tester) async {
    demo_entrypoint.main();
    await tester.pump();

    expect(find.text('Flutter AI Harness'), findsOneWidget);
  });
}
