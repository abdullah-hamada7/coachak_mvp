import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../services/api/api_client.dart';
import '../../../services/subscription/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../../shared/widgets/coachak_components.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _controller = TextEditingController();
  final _messages = <Map<String, String>>[];
  String? _threadId;
  bool _streaming = false;

  final _suggestions = [
    'Create a workout plan for me',
    'I only have dumbbells now',
    'What should I eat post-workout?',
    'How am I progressing?',
  ];

  Future<void> _send([String? text]) async {
    final message = text ?? _controller.text.trim();
    if (message.isEmpty || _streaming) return;

    setState(() {
      _messages.add({'role': 'user', 'content': message});
      _controller.clear();
      _streaming = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      var assistantText = '';

      await for (final eventBlock in api.chatStream(message, threadId: _threadId)) {
        var eventName = 'message';
        for (final line in eventBlock.split('\n')) {
          final trimmed = line.trimRight();
          if (trimmed.startsWith('event:')) {
            eventName = trimmed.substring(6).trim();
            continue;
          }
          if (trimmed.startsWith('data:')) {
            final payload = trimmed.substring(5).trim();
            if (payload.isEmpty) continue;
            Map<String, dynamic>? data;
            try {
              data = jsonDecode(payload) as Map<String, dynamic>;
            } catch (_) {
              continue;
            }

            if (eventName == 'error' && data['status'] == 'subscription_limit') {
              final detail = data['detail'] is Map
                  ? Map<String, dynamic>.from(data['detail'] as Map)
                  : <String, dynamic>{'message': 'Subscription limit reached.'};
              final limitError = SubscriptionLimitException(detail);
              setState(() {
                _messages.add({
                  'role': 'assistant',
                  'content': '${limitError.message} Tap Upgrade to continue.',
                });
              });
              if (mounted) await showSubscriptionLimitPrompt(context, ref, limitError);
              return;
            }

            if (data.containsKey('thread_id')) _threadId = data['thread_id'] as String?;
            if (data.containsKey('content')) {
              assistantText = data['content'] as String;
              setState(() {
                if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
                  _messages.last['content'] = assistantText;
                } else {
                  _messages.add({'role': 'assistant', 'content': assistantText});
                }
              });
            }
          }
        }
      }

      if (assistantText.isEmpty) {
        setState(() => _messages.add({'role': 'assistant', 'content': 'I\'m here to help with your fitness journey!'}));
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        final limitError = SubscriptionLimitException.fromDio(e);
        setState(() => _messages.add({
              'role': 'assistant',
              'content': '${limitError.message} Tap Upgrade to unlock unlimited coaching.',
            }));
        if (mounted) await showSubscriptionLimitPrompt(context, ref, limitError);
      } else {
        final message = e.response?.statusCode == 401
            ? 'Your session expired. Please sign in again, then ask me.'
            : 'Connection error. Is the API running?';
        setState(() => _messages.add({'role': 'assistant', 'content': message}));
      }
    } catch (_) {
      setState(() => _messages.add({'role': 'assistant', 'content': 'Something went wrong. Try asking again.'}));
    } finally {
      setState(() => _streaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Coach')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty ? _SuggestionList(suggestions: _suggestions, onSend: _send) : _MessageList(messages: _messages, streaming: _streaming),
            ),
            _CoachComposer(
              controller: _controller,
              streaming: _streaming,
              onSend: () => _send(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onSend});

  final List<String> suggestions;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(CoachakSpacing.lg),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Semantics(
          header: true,
          child: Text('How can I help today?', style: CoachakTypography.display(context)),
        ),
        const SizedBox(height: CoachakSpacing.sm),
        Text(
          'Ask about workouts, nutrition, or adjusting your plan.',
          style: CoachakTypography.bodyMuted(context),
        ),
        const SizedBox(height: CoachakSpacing.lg),
        CoachakSectionHeader(title: 'Try asking'),
        ...suggestions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: CoachakSpacing.sm),
              child: CoachakGoalCard(
                icon: Icons.chat_bubble_outline,
                title: s,
                subtitle: 'Tap to send',
                selected: false,
                onTap: () => onSend(s),
              ),
            )),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages, required this.streaming});

  final List<Map<String, String>> messages;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(CoachakSpacing.md),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length + (streaming ? 1 : 0),
      itemBuilder: (_, i) {
        if (streaming && i == messages.length) {
          return Padding(
            padding: const EdgeInsets.all(CoachakSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: CoachakSpacing.sm),
                Flexible(child: Text('Coach is thinking...', style: CoachakTypography.bodyMuted(context))),
              ],
            ),
          );
        }
        final msg = messages[i];
        final isUser = msg['role'] == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Semantics(
            label: isUser ? 'You said' : 'Coach said',
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
              child: Container(
                margin: const EdgeInsets.only(bottom: CoachakSpacing.sm),
                padding: const EdgeInsets.all(CoachakSpacing.md),
                decoration: BoxDecoration(
                  color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(CoachakRadius.lg),
                  border: isUser ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Text(msg['content'] ?? '', softWrap: true),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoachComposer extends StatelessWidget {
  const _CoachComposer({
    required this.controller,
    required this.streaming,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool streaming;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          CoachakSpacing.sm,
          CoachakSpacing.sm,
          CoachakSpacing.sm,
          CoachakSpacing.sm + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Ask your coach...',
                  prefixIcon: Icon(Icons.chat_outlined),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: CoachakSpacing.sm),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: streaming ? null : onSend,
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                child: const Icon(Icons.send, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
