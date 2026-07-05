import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router_refresh.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../features/subscription/presentation/paywall_screen.dart';
import '../../../services/api/api_client.dart';
import '../../../services/api/api_errors.dart';
import '../../../services/subscription/subscription_provider.dart';
import '../../../services/user/profile_provider.dart';
import '../../../shared/widgets/coachak_components.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _steps = ['About you', 'Your goals', 'Safety check'];

  int _step = 0;
  final _age = TextEditingController(text: '30');
  final _weight = TextEditingController(text: '75');
  final _height = TextEditingController(text: '175');
  String _sex = 'male';
  String _activity = 'moderate';
  String _experience = 'beginner';
  String _goal = 'general_fitness';
  String _diet = 'omnivore';
  int _daysPerWeek = 3;
  final _equipment = <String>{'bodyweight', 'dumbbell'};
  final _injuries = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  bool _validateStep() {
    if (_step == 0) {
      final age = int.tryParse(_age.text);
      final weight = double.tryParse(_weight.text);
      final height = double.tryParse(_height.text);
      if (age == null || age < 13 || age > 100) {
        setState(() => _error = 'Enter a valid age (13–100).');
        return false;
      }
      if (weight == null || weight <= 0) {
        setState(() => _error = 'Enter a valid weight in kg.');
        return false;
      }
      if (height == null || height <= 0) {
        setState(() => _error = 'Enter a valid height in cm.');
        return false;
      }
    }
    setState(() => _error = null);
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.updateProfile({
        'age': int.parse(_age.text),
        'weight_kg': double.parse(_weight.text),
        'height_cm': double.parse(_height.text),
        'sex': _sex,
        'activity_level': _activity,
        'experience_level': _experience,
        'primary_goal': _goal,
        'dietary_preference': _diet,
        'workout_days_per_week': _daysPerWeek,
        'equipment': _equipment.toList(),
        'injuries': _injuries.toList(),
        'onboarding_complete': true,
      });
      await api.generateWorkoutPlan();
      await api.generateNutritionPlan();
      await ref.read(profileCacheProvider.notifier).setOnboardingComplete(true);
      RouterRefresh.instance.refresh();
      if (mounted) context.go('/home');
    } catch (e) {
      final limit = subscriptionLimitFromError(e);
      if (limit != null && mounted) {
        setState(() => _error = limit.userMessage);
        await showSubscriptionLimitPrompt(context, ref, limit);
      } else {
        setState(() => _error = apiErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _loading ? null : _back,
                tooltip: 'Back',
              )
            : null,
        title: Text(_steps[_step]),
      ),
      body: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CoachakStepIndicator(current: _step, total: _steps.length),
            const SizedBox(height: CoachakSpacing.sm),
            Text(
              'Step ${_step + 1} of ${_steps.length}',
              style: CoachakTypography.bodyMuted(context),
            ),
            const SizedBox(height: CoachakSpacing.lg),
            Expanded(child: _buildStep()),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              const SizedBox(height: CoachakSpacing.sm),
            ],
            FilledButton(
              onPressed: _loading ? null : _next,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_step < _steps.length - 1 ? 'Continue' : 'Build my plans'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return ListView(
          children: [
            Text('Tell us the basics so your coach can personalize safely.', style: CoachakTypography.bodyMuted(context)),
            const SizedBox(height: CoachakSpacing.md),
            TextField(
              controller: _age,
              decoration: const InputDecoration(labelText: 'Age', hintText: 'e.g. 30'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: CoachakSpacing.md),
            TextField(
              controller: _weight,
              decoration: const InputDecoration(labelText: 'Weight (kg)', hintText: 'e.g. 75'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: CoachakSpacing.md),
            TextField(
              controller: _height,
              decoration: const InputDecoration(labelText: 'Height (cm)', hintText: 'e.g. 175'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: CoachakSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _sex,
              decoration: const InputDecoration(labelText: 'Sex'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _sex = v!),
            ),
            const SizedBox(height: CoachakSpacing.md),
            Text('How active are you on a typical week?', style: CoachakTypography.sectionTitle(context)),
            const SizedBox(height: CoachakSpacing.sm),
            ...['sedentary', 'light', 'moderate', 'active', 'very_active'].map((level) {
              return RadioListTile<String>(
                value: level,
                groupValue: _activity,
                onChanged: (v) => setState(() => _activity = v!),
                title: Text(level.replaceAll('_', ' ')),
                contentPadding: EdgeInsets.zero,
              );
            }),
          ],
        );
      case 1:
        return ListView(
          children: [
            Text('Pick your primary goal — we\'ll shape your plan around it.', style: CoachakTypography.bodyMuted(context)),
            const SizedBox(height: CoachakSpacing.md),
            CoachakGoalCard(
              icon: Icons.local_fire_department,
              title: 'Fat loss',
              subtitle: 'Calorie-aware training & nutrition',
              selected: _goal == 'fat_loss',
              onTap: () => setState(() => _goal = 'fat_loss'),
            ),
            const SizedBox(height: CoachakSpacing.sm),
            CoachakGoalCard(
              icon: Icons.fitness_center,
              title: 'Build muscle',
              subtitle: 'Hypertrophy-focused programming',
              selected: _goal == 'hypertrophy',
              onTap: () => setState(() => _goal = 'hypertrophy'),
            ),
            const SizedBox(height: CoachakSpacing.sm),
            CoachakGoalCard(
              icon: Icons.bolt,
              title: 'Get stronger',
              subtitle: 'Progressive strength training',
              selected: _goal == 'strength',
              onTap: () => setState(() => _goal = 'strength'),
            ),
            const SizedBox(height: CoachakSpacing.sm),
            CoachakGoalCard(
              icon: Icons.self_improvement,
              title: 'General fitness',
              subtitle: 'Balanced strength & mobility',
              selected: _goal == 'general_fitness',
              onTap: () => setState(() => _goal = 'general_fitness'),
            ),
            const SizedBox(height: CoachakSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _experience,
              decoration: const InputDecoration(labelText: 'Training experience'),
              items: const [
                DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                DropdownMenuItem(value: 'intermediate', child: Text('Intermediate')),
                DropdownMenuItem(value: 'advanced', child: Text('Advanced')),
              ],
              onChanged: (v) => setState(() => _experience = v!),
            ),
            const SizedBox(height: CoachakSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _diet,
              decoration: const InputDecoration(labelText: 'Diet preference'),
              items: const [
                DropdownMenuItem(value: 'omnivore', child: Text('Omnivore')),
                DropdownMenuItem(value: 'vegetarian', child: Text('Vegetarian')),
                DropdownMenuItem(value: 'vegan', child: Text('Vegan')),
                DropdownMenuItem(value: 'pescatarian', child: Text('Pescatarian')),
              ],
              onChanged: (v) => setState(() => _diet = v!),
            ),
            const SizedBox(height: CoachakSpacing.lg),
            Text('Training frequency: $_daysPerWeek days / week'),
            Slider(
              value: _daysPerWeek.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              label: '$_daysPerWeek',
              onChanged: (v) => setState(() => _daysPerWeek = v.round()),
            ),
            const SizedBox(height: CoachakSpacing.md),
            Text('Equipment you have access to', style: CoachakTypography.sectionTitle(context)),
            const SizedBox(height: CoachakSpacing.sm),
            Wrap(
              spacing: CoachakSpacing.sm,
              runSpacing: CoachakSpacing.sm,
              children: ['bodyweight', 'dumbbell', 'barbell', 'cable', 'bench', 'kettlebell'].map((eq) {
                return FilterChip(
                  label: Text(eq),
                  selected: _equipment.contains(eq),
                  onSelected: (s) => setState(() => s ? _equipment.add(eq) : _equipment.remove(eq)),
                );
              }).toList(),
            ),
          ],
        );
      default:
        return ListView(
          children: [
            Text(
              'Any injuries or limitations? We\'ll avoid exercises that could aggravate them.',
              style: CoachakTypography.bodyMuted(context),
            ),
            const SizedBox(height: CoachakSpacing.md),
            Wrap(
              spacing: CoachakSpacing.sm,
              runSpacing: CoachakSpacing.sm,
              children: ['lower_back', 'knee', 'shoulder', 'wrist'].map((inj) {
                final selected = _injuries.contains(inj);
                return FilterChip(
                  label: Text(inj.replaceAll('_', ' ')),
                  selected: selected,
                  onSelected: (s) => setState(() => s ? _injuries.add(inj) : _injuries.remove(inj)),
                );
              }).toList(),
            ),
            const SizedBox(height: CoachakSpacing.lg),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(CoachakSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified_user, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: CoachakSpacing.sm),
                        Text('Safety first', style: CoachakTypography.sectionTitle(context)),
                      ],
                    ),
                    const SizedBox(height: CoachakSpacing.sm),
                    const Text(
                      'Every plan is validated by our safety engine before you start. '
                      'You can always adjust with your AI coach later.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}
