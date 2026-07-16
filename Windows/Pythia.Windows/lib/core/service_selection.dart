class TranslateServiceSelection {
  const TranslateServiceSelection._();

  static List<String> toggle({
    required List<String> current,
    required String serviceId,
    required bool selected,
    String fallbackServiceId = 'local',
  }) {
    final next = _distinct(current)..remove(serviceId);
    if (selected) next.insert(0, serviceId);
    if (next.isEmpty) next.add(fallbackServiceId);
    return next;
  }

  static List<String> move({
    required List<String> current,
    required String serviceId,
    required int offset,
  }) {
    final next = _distinct(current);
    final from = next.indexOf(serviceId);
    if (from < 0 || offset == 0) return next;
    final to = (from + offset).clamp(0, next.length - 1);
    if (from == to) return next;
    final item = next.removeAt(from);
    next.insert(to, item);
    return next;
  }

  static List<String> _distinct(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }
}
