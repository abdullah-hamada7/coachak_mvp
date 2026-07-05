import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../services/subscription/subscription_provider.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.highlightTier});

  /// Optional tier to highlight when opened from a limit prompt.
  final String? highlightTier;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _selectedProductId;
  bool _activating = false;

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(subscriptionPlansProvider);
    final statusAsync = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your plan'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Maybe later'),
          ),
        ],
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load plans: $e')),
        data: (allPlans) {
          final plans = primaryPaywallPlans(allPlans);
          _selectedProductId ??= plans.firstWhere((p) => p.popular, orElse: () => plans.first).productId;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(CoachakSpacing.md),
                  children: [
                    Text(
                      'مدربك الذكي — تمارين، تغذية، وتحليل الأداء',
                      style: CoachakTypography.sectionTitle(context),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: CoachakSpacing.sm),
                    Text(
                      '7-day free trial on Coach Pro · Cancel anytime',
                      style: CoachakTypography.bodyMuted(context),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: CoachakSpacing.md),
                    statusAsync.when(
                      data: (status) => _CurrentPlanBanner(status: status),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: CoachakSpacing.md),
                    for (final plan in plans) ...[
                      _PlanCard(
                        plan: plan,
                        selected: _selectedProductId == plan.productId,
                        highlighted: widget.highlightTier != null && plan.tier == widget.highlightTier,
                        onTap: () => setState(() => _selectedProductId = plan.productId),
                      ),
                      const SizedBox(height: CoachakSpacing.sm),
                    ],
                    const SizedBox(height: CoachakSpacing.md),
                    const _FeatureComparison(),
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.all(CoachakSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selectedProductId == null || _activating ? null : () => _activate(_selectedProductId!),
                    child: _activating
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_ctaLabel(plans, _selectedProductId)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _ctaLabel(List<SubscriptionPlan> plans, String? productId) {
    final plan = plans.where((p) => p.productId == productId).cast<SubscriptionPlan?>().firstOrNull;
    if (plan == null) return 'Subscribe';
    if (plan.trialDays > 0) return 'Start ${plan.trialDays}-day free trial';
    return 'Subscribe — ${plan.priceEgp} EGP';
  }

  Future<void> _activate(String productId) async {
    setState(() => _activating = true);
    try {
      await ref.read(subscriptionProvider.notifier).activate(productId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription activated!')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Activation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

class _CurrentPlanBanner extends StatelessWidget {
  const _CurrentPlanBanner({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.isFree) return const SizedBox.shrink();
    return Card(
      color: CoachakColors.xp.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.md),
        child: Row(
          children: [
            Icon(Icons.verified, color: CoachakColors.xp),
            const SizedBox(width: CoachakSpacing.sm),
            Expanded(
              child: Text(
                'Current plan: ${tierDisplayName(status.tier)} (${tierDisplayNameAr(status.tier)})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: '${plan.name}, ${plan.priceEgp} Egyptian pounds, ${plan.billingLabel}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoachakRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(CoachakSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoachakRadius.lg),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: highlighted ? scheme.primaryContainer.withValues(alpha: 0.3) : scheme.surface,
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: CoachakSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (plan.popular) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: CoachakColors.xp,
                              borderRadius: BorderRadius.circular(CoachakRadius.pill),
                            ),
                            child: const Text(
                              'Most popular',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(plan.nameAr, style: CoachakTypography.bodyMuted(context)),
                    if (plan.trialDays > 0)
                      Text(
                        '${plan.trialDays}-day free trial',
                        style: TextStyle(color: scheme.primary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${plan.priceEgp}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  Text('EGP · ${plan.billingLabel}', style: CoachakTypography.bodyMuted(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureComparison extends StatelessWidget {
  const _FeatureComparison();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('AI coach chat', '5/wk', '∞'),
      ('Form CV sessions', '3/mo', '∞'),
      ('Food photo scan', '3/mo', '60/mo'),
      ('Workout + nutrition plans', 'Limited', 'Weekly'),
      ('Arabic voice coaching', 'Text only', '∞'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Free vs Coach Pro', style: CoachakTypography.sectionTitle(context)),
            const SizedBox(height: CoachakSpacing.sm),
            Row(
              children: [
                const Expanded(flex: 2, child: SizedBox()),
                Expanded(child: Text('Free', style: CoachakTypography.bodyMuted(context), textAlign: TextAlign.center)),
                Expanded(
                  child: Text('Pro', style: TextStyle(fontWeight: FontWeight.w600, color: CoachakColors.xp), textAlign: TextAlign.center),
                ),
              ],
            ),
            const Divider(),
            for (final row in rows) ...[
              Row(
                children: [
                  Expanded(flex: 2, child: Text(row.$1)),
                  Expanded(child: Text(row.$2, textAlign: TextAlign.center, style: CoachakTypography.bodyMuted(context))),
                  Expanded(child: Text(row.$3, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a dialog and optionally opens the paywall when a subscription limit is hit.
Future<void> showSubscriptionLimitPrompt(
  BuildContext context,
  WidgetRef ref,
  SubscriptionLimitException error,
) async {
  final upgradePlan = tierDisplayName(error.upgradeTier);
  final shouldUpgrade = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(error.title),
      content: Text(
        '${error.userMessage}\n\nTap Upgrade to view ${upgradePlan} plans.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Upgrade to $upgradePlan'),
        ),
      ],
    ),
  );

  if (shouldUpgrade == true && context.mounted) {
    await context.push('/paywall', extra: error.upgradeTier);
  }
}

Future<bool?> openPaywall(BuildContext context, {String? highlightTier}) {
  return context.push<bool>('/paywall', extra: highlightTier);
}
