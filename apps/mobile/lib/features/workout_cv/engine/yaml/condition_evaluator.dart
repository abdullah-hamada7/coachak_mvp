/// Safe evaluator for fitness-trainer YAML conditions (no eval/exec).
class ConditionEvaluator {
  bool evaluate(String condition, Map<String, double> context) {
    final expr = condition.trim();
    if (expr.isEmpty) return false;

    if (expr.contains(' and ')) {
      return expr
          .split(' and ')
          .every((part) => evaluate(part.trim(), context));
    }
    if (expr.contains(' or ')) {
      return expr.split(' or ').any((part) => evaluate(part.trim(), context));
    }

    final match = RegExp(
      r'^abs\(([^)]+)\)\s*(>=|<=|>|<|==)\s*(.+)$',
    ).firstMatch(expr);
    if (match != null) {
      final left = _value(match.group(1)!.trim(), context).abs();
      final op = match.group(2)!;
      final right = _value(match.group(3)!.trim(), context);
      return _compare(left, op, right);
    }

    final cmp = RegExp(
      r'^([a-zA-Z0-9_]+)\s*(>=|<=|>|<|==)\s*(.+)$',
    ).firstMatch(expr);
    if (cmp != null) {
      final left = _value(cmp.group(1)!, context);
      final op = cmp.group(2)!;
      final right = _value(cmp.group(3)!, context);
      return _compare(left, op, right);
    }

    return false;
  }

  double _value(String token, Map<String, double> context) {
    token = token.trim();
    if (token.contains(' ')) {
      final parts = token.split(' ');
      if (parts.length == 3) {
        final a = _value(parts[0], context);
        final op = parts[1];
        final b = _value(parts[2], context);
        return switch (op) {
          '+' => a + b,
          '-' => a - b,
          '*' => a * b,
          '/' => b == 0 ? a : a / b,
          _ => a,
        };
      }
    }
    if (context.containsKey(token)) return context[token]!;
    return double.tryParse(token) ?? 0;
  }

  bool _compare(double left, String op, double right) => switch (op) {
        '>' => left > right,
        '<' => left < right,
        '>=' => left >= right,
        '<=' => left <= right,
        '==' => (left - right).abs() < 0.001,
        _ => false,
      };
}
