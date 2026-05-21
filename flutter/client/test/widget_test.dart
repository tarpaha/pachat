import 'package:flutter_test/flutter_test.dart';

import 'package:pachat_client/main.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PaChatApp());
    expect(find.text('PaChat — Login'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });
}
