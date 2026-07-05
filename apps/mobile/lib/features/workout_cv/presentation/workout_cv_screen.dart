import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../services/api/api_client.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/subscription/subscription_provider.dart';
import '../../../services/voice/coach_voice_service.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../coaching/exercise_coaching_ar.dart';
import '../engine/exercise_engine_factory.dart';
import '../engine/exercise_thresholds.dart';
import '../engine/pose_coordinate_mapper.dart';
import '../engine/pose_input_image.dart';
import '../engine/pose_utils.dart';
import '../engine/yaml/yaml_exercise_loader.dart';
import 'form_overlay_painter.dart';
import 'form_session_summary.dart';

class WorkoutCvScreen extends ConsumerStatefulWidget {
  const WorkoutCvScreen({super.key});

  @override
  ConsumerState<WorkoutCvScreen> createState() => _WorkoutCvScreenState();
}

class _WorkoutCvScreenState extends ConsumerState<WorkoutCvScreen> {
  List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;
  CameraController? _camera;
  PoseDetector? _detector;
  ExerciseRuleEngine? _engine;
  String _exercise = 'squat';
  DifficultyLevel _difficulty = DifficultyLevel.beginner;
  bool _initialized = false;
  bool _running = false;
  bool _busy = false;
  bool _switchingCamera = false;
  int _repCount = 0;
  int _improperRepCount = 0;
  bool _cameraAligned = false;
  int _targetReps = 10;
  int _formScore = 100;
  String _formGrade = 'A';
  List<String> _exercises = kCustomExercises;
  bool _catalogReady = false;
  String? _error;
  String _coachArabicText = ExerciseCoachingAr.waitingForPose;
  String? _lastSpokenCue;
  DateTime? _sessionStart;

  // Latest pose + image metadata for the skeleton overlay.
  Pose? _pose;
  Size? _imageSize;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ensureExerciseCatalogLoaded();
    if (mounted) {
      setState(() {
        _exercises = supportedExercises();
        _catalogReady = true;
        if (!_exercises.contains(_exercise)) _exercise = _exercises.first;
        _setEngine();
      });
    }
    await _prepareCamera();
  }

  Future<void> _prepareCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() => _error = 'Camera permission is required for form analysis.');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }

      _cameras = cameras;
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final selected = back.isNotEmpty ? back.first : cameras.first;
      await _initializeCamera(selected);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not start camera. Try closing other camera apps.');
      }
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    final previous = _camera;
    _camera = null;
    setState(() {
      _initialized = false;
      _error = null;
      _pose = null;
    });

    try {
      await previous?.dispose();
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      _camera = controller;
      _selectedCamera = camera;
      await _detector?.close();
      _detector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.accurate,
        ),
      );
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not start camera. Try closing other camera apps.');
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_running || _switchingCamera || _cameras.length < 2) return;
    final current = _selectedCamera;
    final front = _cameras.where((c) => c.lensDirection == CameraLensDirection.front);
    final back = _cameras.where((c) => c.lensDirection == CameraLensDirection.back);

    CameraDescription? next;
    if (current?.lensDirection == CameraLensDirection.front && back.isNotEmpty) {
      next = back.first;
    } else if (front.isNotEmpty) {
      next = front.first;
    } else {
      final currentIndex = current == null ? -1 : _cameras.indexWhere((c) => c.name == current.name);
      next = _cameras[(currentIndex + 1) % _cameras.length];
    }

    setState(() => _switchingCamera = true);
    try {
      await _initializeCamera(next);
      _syncEngineCamera();
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  void _setEngine() {
    _engine = createExerciseEngine(exercise: _exercise, difficulty: _difficulty);
    _syncEngineCamera();
    _repCount = 0;
    _improperRepCount = 0;
    _cameraAligned = false;
    _coachArabicText = ExerciseCoachingAr.waitingForPose;
  }

  Future<void> _announceInstruction(String arabicText, {bool force = false}) async {
    if (!_running && !force) return;
    if (arabicText.isEmpty) return;

    setState(() => _coachArabicText = arabicText);
    await ref.read(coachVoiceServiceProvider).speakInstruction(arabicText);
  }

  void _handleCueChange(String? cue) {
    if (cue == null || cue == _lastSpokenCue) return;
    _lastSpokenCue = cue;
    final arabic = ExerciseCoachingAr.translateCue(cue, _exercise);
    _announceInstruction(arabic);
  }

  void _syncEngineCamera() {
    syncEngineCameraLens(_engine, _selectedCamera?.lensDirection);
  }

  bool get _prefersFrontCamera {
    if (_exercise == 'dumbbell_fly') return true;
    if (_exercise == 'push_up' && _selectedCamera?.lensDirection == CameraLensDirection.front) {
      return true;
    }
    final def = YamlExerciseCatalog.get(_exercise);
    if (def == null) return false;
    return def.cameraMode == 'front' ||
        (def.cameraMode == 'auto' && _selectedCamera?.lensDirection == CameraLensDirection.front);
  }

  String get _alignmentHintAr {
    if (_prefersFrontCamera) {
      return 'قف أمام الكاميرا — اجعل جسمك وذراعيك ظاهرين بالكامل';
    }
    return 'قف بجانب الكاميرا لتحليل دقيق للشكل';
  }

  Future<void> _startSession() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _detector == null) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _engine?.reset();
    _syncEngineCamera();
    _sessionStart = DateTime.now();
    _lastSpokenCue = null;
    setState(() {
      _running = true;
      _repCount = 0;
      _improperRepCount = 0;
      _cameraAligned = false;
      _pose = null;
      _coachArabicText = ExerciseCoachingAr.waitingForPose;
    });

    try {
      await camera.startImageStream(_processCameraImage);
      final intro = ExerciseCoachingAr.sessionIntro(_exercise, _targetReps);
      await _announceInstruction(intro, force: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = 'Could not start the camera stream. Try again.';
        });
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_switchingCamera || !_running || _busy) return;
    final detector = _detector;
    if (detector == null) return;
    _busy = true;
    try {
      final input = PoseInputImageBuilder.fromCameraImage(
        image: image,
        camera: _selectedCamera!,
        deviceOrientation: _camera!.value.deviceOrientation,
      );
      if (input == null) return;
      final metadata = input.metadata;
      if (metadata == null) return;
      _rotation = metadata.rotation;
      final poses = await detector.processImage(input);
      if (!mounted || !_running) return;
      final pose = selectBestPose(poses);
      if (pose != null) {
        final landmarks = _extractLandmarks(pose);
        if (!hasMinimumPoseCoverage(landmarks)) {
          setState(() => _pose = null);
          return;
        }
        _syncEngineCamera();
        _engine?.processFrame(landmarks, DateTime.now().millisecondsSinceEpoch);
        final newCue = _engine?.currentCue;
        setState(() {
          _pose = pose;
          _imageSize = metadata.size;
          _repCount = _engine?.repCount ?? 0;
          _improperRepCount = _engine?.improperRepCount ?? 0;
          _cameraAligned = _engine?.cameraAligned ?? false;
          _formScore = _engine?.avgFormScore ?? 100;
          _formGrade = _engine?.formGrade ?? 'A';
        });
        _handleCueChange(newCue);
      } else {
        setState(() => _pose = null);
      }
    } catch (_) {
      // Skip bad frames; do not crash the app.
    } finally {
      _busy = false;
    }
  }

  Map<int, PosePoint> _extractLandmarks(Pose pose) {
    final map = <int, PosePoint>{};
    for (final entry in pose.landmarks.entries) {
      final lm = entry.value;
      map[entry.key.index] = PosePoint(lm.x, lm.y, likelihood: lm.likelihood);
    }
    return map;
  }

  Future<void> _stopSession() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    final camera = _camera;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _running = false;
      _pose = null;
    });
    await ref.read(coachVoiceServiceProvider).stop();
    try {
      if (camera != null && camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (_) {}

    final duration = DateTime.now().difference(_sessionStart ?? DateTime.now()).inSeconds;
    final corrections = (_engine?.corrections ?? [])
        .map((c) => {'timestamp_ms': c.timestampMs, 'cue': c.cue, 'severity': c.severity})
        .toList();

    try {
      final result = await ref.read(apiClientProvider).uploadFormSession({
        'exercise': _exercise,
        'rep_count': _repCount,
        'improper_rep_count': _improperRepCount,
        'target_reps': _targetReps,
        'duration_seconds': duration,
        'difficulty': _difficulty.name,
        'corrections': corrections,
        'avg_rom_score': _engine?.romScore ?? 1.0,
        'form_score': _engine?.avgFormScore ?? 100,
        'form_grade': _engine?.formGrade ?? 'A',
      });
      if (!mounted) return;
      final xp = (result['xp_awarded'] as num?)?.toInt() ?? 0;
      final formBonus = (result['form_score_bonus'] as num?)?.toInt() ?? 0;
      final met = result['target_met'] == true;
      final summary = ExerciseCoachingAr.sessionComplete(
        _repCount,
        _targetReps,
        met,
        xp: xp,
        formBonus: formBonus,
      );
      setState(() => _coachArabicText = summary);
      await _announceInstruction(summary, force: true);
      _openTherapistSummary(
        targetMet: met,
        xpAwarded: xp,
        formBonus: formBonus,
        durationSeconds: duration,
      );
      final badges = (result['new_badges'] as List?) ?? [];
      if (badges.isNotEmpty) {
        await ref.read(notificationServiceProvider).showInstantReward(
              title: 'New badge unlocked!',
              body: 'You earned a new achievement. Tap to see it in Progress.',
            );
      }
      ref.invalidate(subscriptionProvider);
    } on DioException catch (e) {
      if (e.response?.statusCode == 402 && mounted) {
        await showSubscriptionLimitPrompt(context, ref, SubscriptionLimitException.fromDio(e));
      } else if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('تم حفظ الجلسة محلياً: $_repCount تكرار')),
        );
        if (_repCount > 0) {
          _openTherapistSummary(
            targetMet: _repCount >= _targetReps,
            xpAwarded: 0,
            formBonus: 0,
            durationSeconds: duration,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('تم حفظ الجلسة محلياً: $_repCount تكرار')),
        );
        if (_repCount > 0) {
          _openTherapistSummary(
            targetMet: _repCount >= _targetReps,
            xpAwarded: 0,
            formBonus: 0,
            durationSeconds: duration,
          );
        }
      }
    }
  }

  FormSessionSummary _buildSessionSummary({
    required bool targetMet,
    required int xpAwarded,
    required int formBonus,
    required int durationSeconds,
  }) {
    return FormSessionSummary(
      exerciseId: _exercise,
      exerciseNameAr: ExerciseCoachingAr.exerciseNameAr(_exercise),
      repCount: _repCount,
      targetReps: _targetReps,
      improperRepCount: _improperRepCount,
      durationSeconds: durationSeconds,
      difficultyAr: _difficulty == DifficultyLevel.pro ? 'متقدم' : 'مبتدئ',
      formScore: _engine?.avgFormScore ?? _formScore,
      formGrade: _engine?.formGrade ?? _formGrade,
      targetMet: targetMet,
      xpAwarded: xpAwarded,
      formBonus: formBonus,
      timestamp: _sessionStart ?? DateTime.now(),
    );
  }

  void _openTherapistSummary({
    required bool targetMet,
    required int xpAwarded,
    required int formBonus,
    required int durationSeconds,
  }) {
    if (!mounted) return;
    context.push(
      '/therapist-summary',
      extra: _buildSessionSummary(
        targetMet: targetMet,
        xpAwarded: xpAwarded,
        formBonus: formBonus,
        durationSeconds: durationSeconds,
      ),
    );
  }

  @override
  void dispose() {
    _running = false;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    ref.read(coachVoiceServiceProvider).stop();
    final camera = _camera;
    _camera = null;
    unawaited(_tearDownCamera(camera));
    _detector?.close();
    super.dispose();
  }

  Future<void> _tearDownCamera(CameraController? camera) async {
    if (camera == null) return;
    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (_) {}
    await camera.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraLabel = switch (_selectedCamera?.lensDirection) {
      CameraLensDirection.front => 'Front camera',
      CameraLensDirection.back => 'Back camera',
      CameraLensDirection.external => 'External camera',
      null => 'Camera',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Analysis'),
        actions: [
          IconButton(
            icon: _switchingCamera
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cameraswitch_outlined),
            tooltip: _running ? 'End the session before switching cameras' : 'Switch camera',
            onPressed: _running || _switchingCamera || _cameras.length < 2 ? null : _switchCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoachakSpacing.sm),
            child: _catalogReady
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: [
                        for (final id in _exercises)
                          ButtonSegment(
                            value: id,
                            label: Text(exerciseDisplayName(id)),
                          ),
                      ],
                      selected: {_exercise},
                      onSelectionChanged: _running
                          ? null
                          : (s) {
                              setState(() {
                                _exercise = s.first;
                                _setEngine();
                              });
                            },
                    ),
                  )
                : const LinearProgressIndicator(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoachakSpacing.md, vertical: CoachakSpacing.xs),
            child: SegmentedButton<DifficultyLevel>(
              segments: const [
                ButtonSegment(value: DifficultyLevel.beginner, label: Text('Beginner')),
                ButtonSegment(value: DifficultyLevel.pro, label: Text('Pro')),
              ],
              selected: {_difficulty},
              onSelectionChanged: _running
                  ? null
                  : (s) {
                      setState(() {
                        _difficulty = s.first;
                        _setEngine();
                      });
                    },
            ),
          ),
          _TargetRepsSelector(
            target: _targetReps,
            enabled: !_running,
            onChanged: (value) => setState(() => _targetReps = value),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(CoachakSpacing.lg),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _switchingCamera
                    ? const Center(child: CircularProgressIndicator())
                    : _initialized && _camera != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: CameraPreview(
                              _camera!,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_running && _pose != null && _imageSize != null)
                                    CustomPaint(
                                      painter: _PosePainter(
                                        pose: _pose!,
                                        imageSize: _imageSize!,
                                        rotation: _rotation,
                                        lensDirection: _selectedCamera?.lensDirection ??
                                            CameraLensDirection.back,
                                      ),
                                    ),
                                  if (_running && _engine != null && _imageSize != null)
                                    CustomPaint(
                                      painter: FormOverlayPainter(
                                        hints: _engine!.overlayHints,
                                        imageSize: _imageSize!,
                                        rotation: _rotation,
                                        lensDirection: _selectedCamera?.lensDirection ??
                                            CameraLensDirection.back,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Semantics(
                              label: cameraLabel,
                              child: Chip(
                                avatar: Icon(
                                  _selectedCamera?.lensDirection == CameraLensDirection.front
                                      ? Icons.camera_front_outlined
                                      : Icons.camera_rear_outlined,
                                  size: 18,
                                ),
                                label: Text(cameraLabel),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 72,
                            left: 16,
                            right: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_running && !_cameraAligned)
                                  Card(
                                    color: Colors.orange.shade800.withValues(alpha: 0.92),
                                    child: Padding(
                                      padding: const EdgeInsets.all(CoachakSpacing.sm),
                                      child: Text(
                                        _alignmentHintAr,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                Card(
                                  color: Colors.black54,
                                  child: Padding(
                                    padding: const EdgeInsets.all(CoachakSpacing.md),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Reps: $_repCount / $_targetReps',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (_improperRepCount > 0)
                                          Text(
                                            'Form fixes: $_improperRepCount',
                                            style: TextStyle(
                                              color: Colors.orange.shade200,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        Text(
                                          'Form score: $_formScore ($_formGrade)',
                                          style: TextStyle(
                                            color: Colors.greenAccent.shade100,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: _CoachingInstructionCard(
                              arabicText: _coachArabicText,
                            ),
                          ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(CoachakSpacing.md),
            child: FilledButton.icon(
              onPressed: _error != null || !_initialized
                  ? null
                  : (_running ? _stopSession : _startSession),
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? 'End Session' : 'Start Session'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachingInstructionCard extends StatelessWidget {
  const _CoachingInstructionCard({
    required this.arabicText,
  });

  final String arabicText;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.78),
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over_outlined, color: Colors.amberAccent, size: 20),
                const SizedBox(width: CoachakSpacing.sm),
                Text(
                  'تعليمات المدرب',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.amberAccent),
                ),
              ],
            ),
            const SizedBox(height: CoachakSpacing.sm),
            Text(
              arabicText,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetRepsSelector extends StatelessWidget {
  const _TargetRepsSelector({
    required this.target,
    required this.enabled,
    required this.onChanged,
  });

  final int target;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CoachakSpacing.md),
      child: Row(
        children: [
          const Text('Target reps'),
          const Spacer(),
          IconButton.outlined(
            onPressed: enabled && target > 1 ? () => onChanged(target - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoachakSpacing.sm),
            child: Text(
              '$target',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton.outlined(
            onPressed: enabled && target < 50 ? () => onChanged(target + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _PosePainter extends CustomPainter {
  _PosePainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  static const _connections = <List<PoseLandmarkType>>[
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    Offset? toOffset(PoseLandmarkType type) {
      final lm = pose.landmarks[type];
      if (lm == null) return null;
      return PoseCoordinateMapper.landmarkToCanvas(
        x: lm.x,
        y: lm.y,
        canvasSize: size,
        imageSize: imageSize,
        rotation: rotation,
        lens: lensDirection,
      );
    }

    for (final pair in _connections) {
      final a = toOffset(pair[0]);
      final b = toOffset(pair[1]);
      if (a != null && b != null) {
        canvas.drawLine(a, b, linePaint);
      }
    }

    for (final lm in pose.landmarks.values) {
      final point = PoseCoordinateMapper.landmarkToCanvas(
        x: lm.x,
        y: lm.y,
        canvasSize: size,
        imageSize: imageSize,
        rotation: rotation,
        lens: lensDirection,
      );
      canvas.drawCircle(point, 5, jointPaint);
    }
  }

  @override
  bool shouldRepaint(_PosePainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.imageSize != imageSize ||
      oldDelegate.rotation != rotation ||
      oldDelegate.lensDirection != lensDirection;
}
