import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

class YamlExerciseDefinition {
  YamlExerciseDefinition._(this.raw);

  final Map<String, dynamic> raw;

  String get name => raw['name'] as String? ?? 'exercise';
  String get displayName => raw['display_name'] as String? ?? name;
  String get type => raw['type'] as String? ?? 'repetition';
  String get cameraMode => raw['camera_mode'] as String? ?? 'side';
  bool get bilateral => raw['bilateral'] == true;
  /// `independent` (default): sum both sides. `unified`: count once per sync rep.
  String get countMode => raw['count_mode'] as String? ?? 'independent';
  /// `average` (default), `min` for deepest joint angle, `primary` to skip combining.
  String get angleStrategy => raw['angle_strategy'] as String? ?? 'average';
  List<String> get sides =>
      (raw['sides'] as List?)?.map((e) => e.toString()).toList() ??
      const ['left', 'right'];
  double get minRepDurationSec => (raw['min_rep_duration'] as num?)?.toDouble() ?? 0.8;
  int get targetDurationSec => (raw['target_duration'] as num?)?.toInt() ?? 30;
  String get holdState => raw['hold_state'] as String? ?? 'hold';

  List<String> get stateOrder =>
      (raw['state_order'] as List?)?.map((e) => e.toString()).toList() ?? [];

  Map<String, dynamic> get states =>
      Map<String, dynamic>.from(raw['states'] as Map? ?? {});

  Map<String, dynamic> get angles =>
      Map<String, dynamic>.from(raw['angles'] as Map? ?? {});

  Map<String, dynamic> get counter =>
      Map<String, dynamic>.from(raw['counter'] as Map? ?? {});

  Map<String, dynamic> get feedback =>
      Map<String, dynamic>.from(raw['feedback'] as Map? ?? {});

  /// Additional angles computed for movement-validation checks only
  /// (not used in state-machine rep counting).
  Map<String, dynamic> get validateAngles =>
      Map<String, dynamic>.from(raw['validate_angles'] as Map? ?? {});

  /// Invariant conditions that must hold for a rep to be valid.
  /// Keyed by condition name, each entry has a `condition` string.
  Map<String, dynamic> get validation =>
      Map<String, dynamic>.from(raw['validation'] as Map? ?? {});

  Map<String, dynamic> get formScoreConfig =>
      Map<String, dynamic>.from(raw['form_score'] as Map? ?? {});

  Map<String, dynamic> get smoothing =>
      Map<String, dynamic>.from(raw['smoothing'] as Map? ?? {});

  static YamlExerciseDefinition parse(String yamlContent) {
    final doc = loadYaml(yamlContent);
    return YamlExerciseDefinition._(Map<String, dynamic>.from(jsonDecode(jsonEncode(doc))));
  }
}

class YamlExerciseCatalog {
  YamlExerciseCatalog._(this.definitions);

  final Map<String, YamlExerciseDefinition> definitions;

  static YamlExerciseCatalog? _instance;

  static Future<YamlExerciseCatalog> load() async {
    if (_instance != null) return _instance!;

    final paths = <String>[];
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final assets = Map<String, dynamic>.from(jsonDecode(manifest) as Map);
      paths.addAll(
        assets.keys.where((k) => k.startsWith('assets/exercises/') && k.endsWith('.yaml')),
      );
    } catch (_) {}

    if (paths.isEmpty) {
      paths.addAll(_fallbackAssets);
    }
    paths.sort();

    final defs = <String, YamlExerciseDefinition>{};
    for (final path in paths) {
      final content = await rootBundle.loadString(path);
      final def = YamlExerciseDefinition.parse(content);
      defs[def.name] = def;
    }
    _instance = YamlExerciseCatalog._(defs);
    return _instance!;
  }

  static const _fallbackAssets = [
    'assets/exercises/squat.yaml',
    'assets/exercises/push_up.yaml',
    'assets/exercises/lunge.yaml',
    'assets/exercises/bicep_curl.yaml',
    'assets/exercises/deadlift.yaml',
    'assets/exercises/plank.yaml',
    'assets/exercises/shoulder_press.yaml',
    'assets/exercises/glute_bridge.yaml',
    'assets/exercises/hammer_curl.yaml',
    'assets/exercises/lateral_raise.yaml',
    'assets/exercises/tricep_dip.yaml',
    'assets/exercises/side_lunge.yaml',
    'assets/exercises/mountain_climber.yaml',
    'assets/exercises/high_knees.yaml',
    'assets/exercises/jumping_jack.yaml',
    'assets/exercises/leg_raise.yaml',
    'assets/exercises/calf_raise.yaml',
    'assets/exercises/wall_sit.yaml',
    'assets/exercises/heel_slides.yaml',
    'assets/exercises/straight_leg_raise.yaml',
    'assets/exercises/ankle_pump.yaml',
    'assets/exercises/quad_sets.yaml',
  ];

  static List<String> exerciseIds() =>
      _instance?.definitions.keys.toList() ?? [];

  static YamlExerciseDefinition? get(String id) => _instance?.definitions[id];
}
