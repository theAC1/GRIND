int _idCounter = 0;

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_idCounter++).toRadixString(36)}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Zahl in deutscher Schreibweise ohne überflüssige Nachkommastellen:
/// 100.0 → "100", 97.5 → "97,5".
String fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

/// Akzeptiert "97,5" und "97.5".
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
