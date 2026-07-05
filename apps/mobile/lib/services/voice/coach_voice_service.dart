import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';

final coachVoiceServiceProvider = Provider<CoachVoiceService>((ref) {
  final service = CoachVoiceService(ref.watch(apiClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Fetches ElevenLabs Arabic speech from the API and plays it on-device.
class CoachVoiceService {
  CoachVoiceService(this._api);

  final ApiClient _api;
  final AudioPlayer _player = AudioPlayer();
  String? lastInstruction;

  Future<void> speakInstruction(String arabicText) async {
    final text = arabicText.trim();
    if (text.isEmpty) return;

    lastInstruction = text;
    try {
      await _player.stop();
      final result = await _api.fetchCoachSpeech(text);
      final audioB64 = result['audio_base64'] as String?;
      if (audioB64 == null || audioB64.isEmpty) {
        debugPrint('Coach TTS: text-only (no ElevenLabs audio returned)');
        return;
      }

      final bytes = base64Decode(audioB64);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/coach_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(bytes, flush: true);
      await _player.play(DeviceFileSource(file.path));
      await _player.onPlayerComplete.first.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
    } catch (e, st) {
      debugPrint('Coach TTS failed: $e\n$st');
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
