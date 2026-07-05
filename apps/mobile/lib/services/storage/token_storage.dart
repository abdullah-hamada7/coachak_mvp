import 'package:hive/hive.dart';

class TokenStorage {
  static const _key = 'auth_token';
  static late Box _box;
  static bool ready = false;

  static Future<void> init() async {
    _box = await Hive.openBox('coachak');
    ready = true;
  }

  static String? get token => ready ? _box.get(_key) as String? : null;

  static Future<void> saveToken(String token) async {
    if (!ready) return;
    await _box.put(_key, token);
  }

  static Future<void> clear() async {
    if (!ready) return;
    await _box.delete(_key);
  }
}
