import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.productId,
    required this.tier,
    required this.name,
    required this.nameAr,
    required this.billingPeriod,
    required this.priceEgp,
    required this.trialDays,
    required this.popular,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) => SubscriptionPlan(
        productId: json['product_id'] as String,
        tier: json['tier'] as String,
        name: json['name'] as String,
        nameAr: json['name_ar'] as String? ?? json['name'] as String,
        billingPeriod: json['billing_period'] as String,
        priceEgp: json['price_egp'] as int,
        trialDays: json['trial_days'] as int? ?? 0,
        popular: json['popular'] as bool? ?? false,
      );

  final String productId;
  final String tier;
  final String name;
  final String nameAr;
  final String billingPeriod;
  final int priceEgp;
  final int trialDays;
  final bool popular;

  String get billingLabel {
    switch (billingPeriod) {
      case 'annual':
        return 'سنوي';
      case 'quarterly':
        return '٣ أشهر';
      default:
        return 'شهري';
    }
  }
}

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.tier,
    required this.isActive,
    this.isOwner = false,
    this.productId,
    this.expiresAt,
    this.limits = const {},
    this.usage = const {},
    this.features = const [],
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) => SubscriptionStatus(
        tier: json['tier'] as String? ?? 'free',
        isActive: json['is_active'] as bool? ?? false,
        isOwner: json['is_owner'] as bool? ?? false,
        productId: json['product_id'] as String?,
        expiresAt: json['expires_at'] as String?,
        limits: Map<String, dynamic>.from(json['limits'] as Map? ?? {}),
        usage: Map<String, dynamic>.from(json['usage'] as Map? ?? {}),
        features: (json['features'] as List?)?.cast<String>() ?? const [],
      );

  final String tier;
  final bool isActive;
  final bool isOwner;
  final String? productId;
  final String? expiresAt;
  final Map<String, dynamic> limits;
  final Map<String, dynamic> usage;
  final List<String> features;

  bool get isFree => tier == 'free' && !isOwner;

  bool get hasUnlimitedAccess => isOwner || tier == 'elite';

  int? limitFor(String feature) {
    if (isOwner) return null;
    final value = limits[feature];
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  int usedFor(String feature) {
    final value = usage[feature];
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  bool isUnlimited(String feature) => isOwner || limitFor(feature) == null;

  bool isAtLimit(String feature) {
    if (isOwner) return false;
    final limit = limitFor(feature);
    if (limit == null) return false;
    return usedFor(feature) >= limit;
  }

  bool canUse(String feature) => !isAtLimit(feature);
}

class SubscriptionLimitException implements Exception {
  SubscriptionLimitException(this.detail);

  factory SubscriptionLimitException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is Map) {
      return SubscriptionLimitException(Map<String, dynamic>.from(data['detail'] as Map));
    }
    return SubscriptionLimitException({'message': error.message ?? 'Subscription limit reached'});
  }

  final Map<String, dynamic> detail;

  String get feature => detail['feature'] as String? ?? 'feature';
  String get upgradeTier => detail['upgrade_tier'] as String? ?? 'coach_pro';
  String get title => detail['title'] as String? ?? 'Upgrade your plan';
  int? get limit => detail['limit'] as int?;
  int? get used => detail['used'] as int?;

  String get message => detail['message'] as String? ?? userMessage;

  String get userMessage {
    if (detail['message'] is String && (detail['message'] as String).isNotEmpty) {
      return detail['message'] as String;
    }
    final plan = tierDisplayName(upgradeTier);
    final label = _featureLabel(feature);
    if (limit == 0) {
      return 'Your Free plan does not include $label. Upgrade to $plan to unlock it.';
    }
    if (limit != null && used != null) {
      return 'You\'ve used $used of $limit $label. Upgrade to $plan to continue.';
    }
    return 'You\'ve reached your plan limit for $label. Upgrade to $plan to continue.';
  }

  static String _featureLabel(String feature) {
    switch (feature) {
      case 'form_sessions':
        return 'form analysis sessions';
      case 'chat_messages':
        return 'coach messages';
      case 'chat_messages_week':
        return 'coach messages this week';
      case 'food_scans':
        return 'food photo scans';
      case 'voice_cues':
        return 'voice coaching cues';
      case 'workout_generations':
        return 'workout plan generations';
      case 'nutrition_generations':
        return 'nutrition plan generations';
      default:
        return feature.replaceAll('_', ' ');
    }
  }
}

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, SubscriptionStatus>(SubscriptionNotifier.new);

class SubscriptionNotifier extends AsyncNotifier<SubscriptionStatus> {
  @override
  Future<SubscriptionStatus> build() async {
    return _fetch();
  }

  Future<SubscriptionStatus> _fetch() async {
    final data = await ref.read(apiClientProvider).getSubscriptionStatus();
    return SubscriptionStatus.fromJson(data);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _fetch());
  }

  Future<SubscriptionStatus> activate(String productId) async {
    final data = await ref.read(apiClientProvider).activateSubscription(productId);
    final status = SubscriptionStatus.fromJson(data);
    state = AsyncData(status);
    return status;
  }
}

final subscriptionPlansProvider = FutureProvider<List<SubscriptionPlan>>((ref) async {
  final data = await ref.read(apiClientProvider).getSubscriptionPlans();
  final plans = (data['plans'] as List?) ?? [];
  return plans.map((p) => SubscriptionPlan.fromJson(Map<String, dynamic>.from(p as Map))).toList();
});

/// Primary paid plans shown on the paywall (monthly + annual Pro).
List<SubscriptionPlan> primaryPaywallPlans(List<SubscriptionPlan> all) {
  const ids = {
    'coachak_pro_monthly_egp',
    'coachak_pro_annual_egp',
    'coachak_train_monthly_egp',
    'coachak_fuel_monthly_egp',
    'coachak_elite_monthly_egp',
  };
  return all.where((p) => ids.contains(p.productId)).toList()
    ..sort((a, b) {
      if (a.popular != b.popular) return a.popular ? -1 : 1;
      return a.priceEgp.compareTo(b.priceEgp);
    });
}

String tierDisplayName(String tier) {
  switch (tier) {
    case 'train':
      return 'Train';
    case 'fuel':
      return 'Fuel';
    case 'train_fuel':
      return 'Train + Fuel';
    case 'coach_pro':
      return 'Coach Pro';
    case 'elite':
      return 'Elite';
    default:
      return 'Free';
  }
}

String tierDisplayNameAr(String tier) {
  switch (tier) {
    case 'train':
      return 'تدريب';
    case 'fuel':
      return 'تغذية';
    case 'train_fuel':
      return 'تدريب + تغذية';
    case 'coach_pro':
      return 'كوتش برو';
    case 'elite':
      return 'نخبة';
    default:
      return 'مجاني';
  }
}
