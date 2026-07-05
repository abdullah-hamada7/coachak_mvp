import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../api/api_client.dart';
import '../storage/token_storage.dart';
import '../../core/router/router_refresh.dart';

class ProfileCache {
  const ProfileCache({this.onboardingComplete, this.displayName});

  final bool? onboardingComplete;
  final String? displayName;

  ProfileCache copyWith({bool? onboardingComplete, String? displayName}) => ProfileCache(
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        displayName: displayName ?? this.displayName,
      );
}

class ProfileCacheNotifier extends Notifier<ProfileCache> {
  static const _boxKey = 'profile_cache';

  @override
  ProfileCache build() {
    final box = Hive.box('coachak');
    return ProfileCache(
      onboardingComplete: box.get('${_boxKey}_onboarding') as bool?,
      displayName: box.get('${_boxKey}_name') as String?,
    );
  }

  Future<void> refreshFromApi() async {
    try {
      final profile = await ref.read(apiClientProvider).getProfile();
      final complete = profile['onboarding_complete'] as bool? ?? false;
      final name = profile['display_name'] as String?;
      await _persist(complete, name);
      state = ProfileCache(onboardingComplete: complete, displayName: name);
      RouterRefresh.instance.refresh();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await TokenStorage.clear();
        await clear();
      }
    } catch (_) {
      // Keep cached values on network failure.
    }
  }

  Future<void> setOnboardingComplete(bool value, {String? displayName}) async {
    await _persist(value, displayName ?? state.displayName);
    state = state.copyWith(onboardingComplete: value, displayName: displayName);
    RouterRefresh.instance.refresh();
  }

  Future<void> clear() async {
    final box = Hive.box('coachak');
    await box.delete('${_boxKey}_onboarding');
    await box.delete('${_boxKey}_name');
    state = const ProfileCache();
    RouterRefresh.instance.refresh();
  }

  Future<void> _persist(bool onboarding, String? name) async {
    final box = Hive.box('coachak');
    await box.put('${_boxKey}_onboarding', onboarding);
    if (name != null) await box.put('${_boxKey}_name', name);
  }
}

final profileCacheProvider = NotifierProvider<ProfileCacheNotifier, ProfileCache>(ProfileCacheNotifier.new);
