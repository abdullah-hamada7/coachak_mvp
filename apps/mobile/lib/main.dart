import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'services/notifications/notification_service.dart';
import 'services/storage/token_storage.dart';

Future<void> main() async {
  String? initError;

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
      return true;
    };

    try {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      await TokenStorage.init();
      final notifications = NotificationService();
      await notifications.init();
    } catch (e, st) {
      initError = e.toString();
      debugPrint('Init failed: $e\n$st');
    }
    runApp(ProviderScope(child: initError == null ? const CoachakApp() : _CrashScreen(initError!)));
  }, (error, stack) {
    debugPrint('Zone error: $error\n$stack');
  });
}

class _CrashScreen extends StatelessWidget {
  const _CrashScreen(this.error);
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Coachak could not start', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
