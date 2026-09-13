import 'dart:convert';
import 'dart:math';

/// Spine's native findBone aborts the process for an empty name.
T? resolveOptionalRigBone<T>(String? name, T? Function(String) findBone) {
  if (name == null || name.trim().isEmpty) return null;
  return findBone(name);
}

class RigMotion {
  const RigMotion([this.yaw = 0, this.pitch = 0, this.roll = 0]);
  final double yaw;
  final double pitch;
  final double roll;

  RigMotion scaled(double value) =>
      RigMotion(yaw * value, pitch * value, roll * value);

  RigMotion blend(RigMotion other, double t) => RigMotion(
    yaw + (other.yaw - yaw) * t,
    pitch + (other.pitch - pitch) * t,
    roll + (other.roll - roll) * t,
  );
}

class CharacterPerformanceProfile {
  CharacterPerformanceProfile._(this.drivers, this.aimBones, this.rollBones);

  final List<Map<String, dynamic>> drivers;
  final Map<String, String> aimBones;
  final Map<String, String> rollBones;

  bool get hasResourceDrivers => drivers.isNotEmpty;

  /// No bone mappings are guessed when a resource lacks legacy DriverDefs.
  factory CharacterPerformanceProfile.fallback() =>
      CharacterPerformanceProfile._(const [], const {}, const {});

  factory CharacterPerformanceProfile.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final gesture = json['emotionalGesture'] as Map<String, dynamic>?;
    final rig = json['rigConfig'] as Map<String, dynamic>?;
    Map<String, String> bones(String key) => {
      for (final entry in (rig?[key] as Map<String, dynamic>? ?? {}).entries)
        if (entry.value is Map && (entry.value as Map)['bone'] is String)
          entry.key: (entry.value as Map)['bone'] as String,
    };
    final drivers = <Map<String, dynamic>>[];
    for (final entry in gesture?['DriverDefs'] as List? ?? const []) {
      if (entry is! Map || entry['Spec'] is! String) continue;
      try {
        final spec = jsonDecode(entry['Spec'] as String);
        if (spec is Map<String, dynamic> && spec['id'] is String) {
          drivers.add(spec);
        }
      } on FormatException {
        // One malformed optional driver must not disable all character motion.
      }
    }
    return CharacterPerformanceProfile._(
      drivers,
      bones('aimSlots'),
      bones('rollSlots'),
    );
  }
}

/// Samples local resource drivers with bounded, non-accumulating offsets.
class CharacterPerformanceDirector {
  CharacterPerformanceDirector(this.profile, {Random? random})
    : _random = random ?? Random();

  final CharacterPerformanceProfile profile;
  final Random _random;
  Map<String, dynamic>? _driver;
  String? _emotion;
  double _elapsed = 0;
  double _transition = 1;
  double _hold = 1;
  double _strength = 0.3;
  Map<String, RigMotion> _from = {};
  Map<String, RigMotion> _target = {};
  final Map<String, double> _followerDelays = {};
  final Map<String, RigMotion> _parts = {};

  // Unsupported resource schemas use small, slow targets with actual rests,
  // never an extra oscillator layered over the resource's existing motion.
  static const _fallbackDriver = <String, dynamic>{
    'id': 'neutral_n_fallback',
    'driver': 'head',
    'yawMin': -0.08,
    'yawMax': 0.08,
    'pitchMin': -0.06,
    'pitchMax': 0.08,
    'rollMin': -0.035,
    'rollMax': 0.035,
    'transitionMin': 1.4,
    'transitionMax': 2.2,
    'holdMin': 2.8,
    'holdMax': 4.5,
    'followers': [
      {'part': 'eye', 'scale': 0.4, 'delay': 0.15},
      {'part': 'body', 'scale': 0.2, 'delay': 0.55},
    ],
  };

  double _number(Map value, String key, double fallback) {
    final number = value[key];
    return number is num && number.isFinite ? number.toDouble() : fallback;
  }

  double _range(
    Map value,
    String key,
    double fallback,
    double low,
    double high,
  ) {
    final a = _number(value, '${key}Min', fallback).clamp(low, high);
    final b = _number(value, '${key}Max', fallback).clamp(low, high);
    return min(a, b) + _random.nextDouble() * (a - b).abs();
  }

  Map<String, RigMotion> sample({
    required double delta,
    required String emotion,
    required bool speaking,
    required double energy,
    bool suppressed = false,
  }) {
    final dt = delta.isFinite ? delta.clamp(0.0, 0.05).toDouble() : 0.0;
    if (_driver == null ||
        _emotion != emotion ||
        _elapsed >= _transition + _hold) {
      var candidates = profile.drivers
          .where((d) => (d['id'] as String).startsWith('${emotion}_n_'))
          .toList();
      if (candidates.isEmpty) {
        candidates = profile.drivers
            .where((d) => (d['id'] as String).startsWith('neutral_n_'))
            .toList();
      }
      final alternatives = candidates.where((d) => d != _driver).toList();
      if (alternatives.isNotEmpty) candidates = alternatives;
      _driver = candidates.isEmpty
          ? _fallbackDriver
          : candidates[_random.nextInt(candidates.length)];
      // A new lead part starts at its own current pose. Reusing one shared
      // head target here used to transfer it abruptly to the body or eyes.
      _from = Map.of(_parts);
      final motion = RigMotion(
        _range(_driver!, 'yaw', 0, -1, 1),
        _range(_driver!, 'pitch', 0, -1, 1),
        _range(_driver!, 'roll', 0, -1, 1),
      );
      _target = {(_driver!['driver'] as String? ?? 'head'): motion};
      _followerDelays.clear();
      for (final follower in _driver!['followers'] as List? ?? const []) {
        if (follower is! Map || follower['part'] is! String) continue;
        final part = follower['part'] as String;
        if (_target.containsKey(part)) continue;
        _target[part] = motion.scaled(
          _number(follower, 'scale', 0).clamp(-1.0, 1.0),
        );
        _followerDelays[part] = _number(
          follower,
          'delay',
          0.3,
        ).clamp(0.06, 1.0);
      }
      _transition = _range(_driver!, 'transition', 1, 0.4, 4);
      _hold = _range(_driver!, 'hold', 1.5, 0.2, 5);
      _emotion = emotion;
      _elapsed = 0;
    }
    _elapsed += dt;
    final t = (_elapsed / _transition).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    // Idle motion should read as a living character's breathing and attention,
    // rather than a continuously animated puppet. Keep a visible but bounded
    // baseline so the character does not become a statue between interactions.
    final targetStrength = suppressed
        ? 0.0
        : speaking
        ? 0.85
        : 0.30;
    // Mouth energy includes syllable-rate pulses, especially the Android
    // fallback envelope. It must not shake the head/body. Keep the argument
    // for callers that still use that same energy for lip sync, and ease only
    // the broad speaking state (350 ms attack, 500 ms release, 120 ms hide).
    final strengthResponse = suppressed
        ? 0.12
        : speaking
        ? 0.35
        : 0.9;
    _strength +=
        (targetStrength - _strength) * (1 - exp(-dt / strengthResponse));
    for (final part in {
      'head',
      'body',
      'eye',
      ..._parts.keys,
      ..._target.keys,
    }) {
      final desired = (_from[part] ?? const RigMotion()).blend(
        _target[part] ?? const RigMotion(),
        eased,
      );
      final response = _followerDelays[part] ?? 0.12;
      _parts[part] = (_parts[part] ?? const RigMotion()).blend(
        desired,
        1 - exp(-dt / response),
      );
    }
    return Map.unmodifiable({
      for (final entry in _parts.entries)
        entry.key: entry.value.scaled(_strength),
    });
  }
}

/// Interpolates coarse player notifications, but stops extrapolating on stalls.
Duration interpolatedSpeechPosition(Duration anchor, Duration sinceAnchor) =>
    anchor + Duration(microseconds: min(sinceAnchor.inMicroseconds, 250000));
