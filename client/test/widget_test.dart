import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pachat_client/main.dart';

void main() {
  testWidgets('Connect screen loads without nickname or presence', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PaChatApp());
    await tester.pumpAndSettle();
    expect(find.text('PaChat — Connect'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Nickname'), findsNothing);
  });
}
