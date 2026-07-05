import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:coachak/app.dart';
import 'package:coachak/services/storage/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('coachak_test_');
    Hive.init(dir.path);
    await TokenStorage.init();
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('Coachak app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CoachakApp()));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
