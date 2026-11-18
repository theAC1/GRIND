import 'models.dart';
import 'util.dart';
import 'workout.dart';

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_two(d.day)}.${_two(d.month)}.${d.year}';

/// "Heute", "Morgen", "Gestern" oder das Datum.
String relativeDate(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = dateOnly(d).difference(today).inHours / 24;
  final days = diff.round();
  return switch (days) {
    0 => 'Heute · ${formatDate(d)}',
    1 => 'Morgen · ${formatDate(d)}',
    -1 => 'Gestern · ${formatDate(d)}',
    _ => formatDate(d),
  };
}

String fmtKg(double kg) => '${fmtNum(kg)} kg';

/// Vorgabe in einer Zeile, z. B. "3 × 10 · 60 kg · Pause 90 s".
String entrySummary(SessionEntry e) {
  final parts = <String>[
    e.reps.trim().isEmpty
        ? '${e.sets} ${e.sets == 1 ? 'Satz' : 'Sätze'}'
        : '${e.sets} × ${e.reps.trim()}',
    if (e.weightKg != null) fmtKg(e.weightKg!),
    if (e.load.trim().isNotEmpty) e.load.trim(),
    if (e.restSec != null && e.restSec! > 0) 'Pause ${e.restSec} s',
  ];
  return parts.join(' · ');
}

/// Ein protokollierter Satz, z. B. "100 kg × 8", "12 Wdh." oder "30 s".
String setLogText(SetLog l, String unit) {
  final reps = l.reps;
  if (l.weightKg != null) {
    return reps == null ? fmtKg(l.weightKg!) : '${fmtKg(l.weightKg!)} × $reps';
  }
  return reps == null ? '✓' : '$reps $unit';
}

/// Erledigte Sätze einer Übung als Liste von Kurztexten.
List<String> doneSetTexts(SessionEntry e) {
  final unit = parseRepsTarget(e.reps).unit;
  return [
    for (final l in e.logs)
      if (l.done) setLogText(l, unit),
  ];
}

/// Reintext-Version einer Einheit zum Teilen (Messenger, E-Mail).
/// Mit [exerciseOf] werden die Video-Links der Übungen angehängt.
String sessionAsText(
  TrainingSession s,
  Athlete? athlete, {
  Exercise? Function(String id)? exerciseOf,
}) {
  final b = StringBuffer()..writeln(s.title);
  if (athlete != null) b.writeln('Athlet: ${athlete.name}');
  b.writeln('Datum: ${formatDate(s.date)}');
  if (s.notes.trim().isNotEmpty) b.writeln('Hinweis: ${s.notes.trim()}');
  b.writeln();
  for (var i = 0; i < s.entries.length; i++) {
    final e = s.entries[i];
    b.writeln('${i + 1}. ${e.name} (${e.category.label})');
    b.writeln('   ${entrySummary(e)}');
    if (e.note.trim().isNotEmpty) b.writeln('   → ${e.note.trim()}');
    final links = exerciseOf?.call(e.exerciseId)?.videoLinks ?? const [];
    for (final link in links) {
      b.writeln('   Video: $link');
    }
  }
  return b.toString().trimRight();
}
