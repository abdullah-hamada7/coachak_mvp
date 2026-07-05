import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router_refresh.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../services/api/api_client.dart';
import '../../../services/storage/token_storage.dart';
import '../../../services/user/profile_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.register(_email.text.trim(), _password.text, _name.text.trim());
      await TokenStorage.saveToken(res['access_token'] as String);
      await ref.read(profileCacheProvider.notifier).setOnboardingComplete(false, displayName: _name.text.trim());
      RouterRefresh.instance.refresh();
      if (mounted) context.go('/welcome');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      setState(() {
        _error = status == 409
            ? 'That email is already registered. Try signing in instead.'
            : 'Could not reach Coachak API. Check the server connection and try again.';
      });
    } catch (_) {
      setState(() => _error = 'Could not create account. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(CoachakSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Start your fitness journey with a coach that knows you.',
              style: CoachakTypography.bodyMuted(context),
            ),
            const SizedBox(height: CoachakSpacing.lg),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'What should we call you?'),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
            ),
            const SizedBox(height: CoachakSpacing.md),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: CoachakSpacing.md),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 8 characters',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
            ),
            if (_error != null) ...[
              const SizedBox(height: CoachakSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: CoachakSpacing.lg),
            FilledButton(
              onPressed: _loading ? null : _register,
              child: _loading ? const CircularProgressIndicator() : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
