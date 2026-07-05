import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../services/storage/token_storage.dart';

class RouterRefresh extends ChangeNotifier {
  RouterRefresh._();
  static final RouterRefresh instance = RouterRefresh._();

  void refresh() => notifyListeners();
}

bool? readOnboardingComplete() {
  try {
    if (!TokenStorage.ready) return null;
    return Hive.box('coachak').get('profile_cache_onboarding') as bool?;
  } catch (_) {
    return null;
  }
}

String? routerRedirect(String location) {
  if (!TokenStorage.ready) {
    return location == '/login' ? null : '/login';
  }
  final token = TokenStorage.token;
  final isAuthRoute = location == '/login' || location == '/register';
  final isOnboardingRoute = location == '/welcome' || location == '/onboarding';
  final onboardingComplete = readOnboardingComplete();

  if (token == null) {
    return isAuthRoute ? null : '/login';
  }

  if (isAuthRoute) {
    if (onboardingComplete == false) return '/welcome';
    return '/home';
  }

  if (onboardingComplete == false && !isOnboardingRoute) {
    return '/welcome';
  }

  if (onboardingComplete == true && isOnboardingRoute) {
    return '/home';
  }

  return null;
}
