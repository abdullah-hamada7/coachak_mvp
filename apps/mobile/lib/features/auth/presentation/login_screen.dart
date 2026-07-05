import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router_refresh.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../services/api/api_client.dart';
import '../../../services/storage/token_storage.dart';
import '../../../services/user/profile_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.login(_email.text.trim(), _password.text);
      await TokenStorage.saveToken(res['access_token'] as String);
      await ref.read(profileCacheProvider.notifier).refreshFromApi();
      RouterRefresh.instance.refresh();
      if (mounted) {
        final complete = ref.read(profileCacheProvider).onboardingComplete ?? false;
        context.go(complete ? '/home' : '/welcome');
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      setState(() {
        _error = status == 401
            ? 'Incorrect email or password. Please try again.'
            : 'Could not reach Coachak API. Check the server connection and try again.';
      });
    } catch (_) {
      setState(() => _error = 'Could not sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CoachakSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: CoachakSpacing.xl),
              Semantics(
                label: 'Coachak logo',
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.fitness_center, size: 40, color: Theme.of(context).colorScheme.primary),
                ),
              ),
              const SizedBox(height: CoachakSpacing.lg),
              Semantics(
                header: true,
                child: Text('Welcome back', style: CoachakTypography.display(context), textAlign: TextAlign.center),
              ),
              const SizedBox(height: CoachakSpacing.sm),
              Text(
                'Your coach, plans, and streaks are waiting.',
                style: CoachakTypography.bodyMuted(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CoachakSpacing.xl),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: CoachakSpacing.md),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                  ),
                ),
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: CoachakSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
              const SizedBox(height: CoachakSpacing.lg),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: CoachakSpacing.md),
              TextButton(
                onPressed: () => context.go('/register'),
                child: const Text('New here? Create a free account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
