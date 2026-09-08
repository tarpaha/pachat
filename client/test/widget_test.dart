import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
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
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('Created by me'), findsOneWidget);
    expect(find.text('Create friend'), findsOneWidget);
    await tester.tap(find.text('Received keys'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import public key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
