import 'character_expression.dart';
import 'character_performance.dart';

class QueuedPerformance {
  const QueuedPerformance(
    this.action,
    this.expression,
    this.expiresAt, {
    this.motionGroupId,
  });

  const QueuedPerformance.motion(
    this.motionGroupId,
    this.expression,
    this.expiresAt,
  ) : action = CharacterAction.none;

  final CharacterAction action;
  final CharacterExpression expression;
  final DateTime expiresAt;
  final String? motionGroupId;
}

/// Short-lived intentions, never a backlog of obsolete conversation gestures.
class CharacterPerformanceQueue {
  final _items = <QueuedPerformance>[];
  void clear() => _items.clear();
  void add(
    CharacterAction action,
    CharacterExpression expression,
    DateTime now,
  ) {
    _items.removeWhere((item) => !item.expiresAt.isAfter(now));
    if (action == CharacterAction.none) return;
    if (_items.any(
      (item) => item.action == action && item.expression == expression,
    )) {
      return;
    }
    if (_items.length >= 2) _items.removeAt(0);
    _items.add(
      QueuedPerformance(
        action,
        expression,
        now.add(const Duration(seconds: 5)),
      ),
    );
  }

  void addMotionGroup(
    String motionGroupId,
    CharacterExpression expression,
    DateTime now,
  ) {
    final normalized = motionGroupId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    _items.removeWhere((item) => !item.expiresAt.isAfter(now));
    if (_items.any((item) => item.motionGroupId == normalized)) return;
    if (_items.length >= 2) _items.removeAt(0);
    _items.add(
      QueuedPerformance.motion(
        normalized,
        expression,
        now.add(const Duration(seconds: 5)),
      ),
    );
  }

  QueuedPerformance? take(DateTime now) {
    _items.removeWhere((item) => !item.expiresAt.isAfter(now));
    return _items.isEmpty ? null : _items.removeAt(0);
  }

  bool get isNotEmpty => _items.isNotEmpty;
}
