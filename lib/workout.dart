import 'models.dart';

/// Zielwert aus dem Freitext der Vorgabe: "8–12" → 8 Wdh., "30 s" → 30 s.
class RepsTarget {
  const RepsTarget(this.value, this.unit);

  final int? value;

  /// "Wdh.", "s" oder "min".
  final String unit;

  int get step => unit == 's' ? 5 : 1;
}

RepsTarget parseRepsTarget(String reps) {
  final lower = reps.toLowerCase();
  final number = RegExp(r'\d+').firstMatch(lower);
  final String unit;
  if (RegExp(r'\d\s*(s|sek|sec|sekunden)(?![a-zäöü])').hasMatch(lower)) {
    unit = 's';
  } else if (RegExp(r'\d\s*(min|minuten)(?![a-zäöü])').hasMatch(lower)) {
    unit = 'min';
  } else {
    unit = 'Wdh.';
  }
  return RepsTarget(number == null ? null : int.parse(number.group(0)!), unit);
}

/// Die Satzliste, mit der der Athlet arbeitet: bereits protokollierte Sätze,
/// aufgefüllt bis zur vorgegebenen Satzzahl. Offene Sätze übernehmen die
/// Werte des letzten Satzes, sonst die Vorgabe.
List<SetLog> workingLogs(SessionEntry e) {
  final logs = [...e.logs];
  final target = parseRepsTarget(e.reps);
  final count = e.sets < 1 ? 1 : e.sets;
  while (logs.length < count) {
    logs.add(
      logs.isEmpty
          ? SetLog(reps: target.value, weightKg: e.weightKg)
          : SetLog(reps: logs.last.reps, weightKg: logs.last.weightKg),
    );
  }
  return logs;
}

/// Hakt Satz [index] ab bzw. nimmt den Haken wieder weg.
SessionEntry toggleSet(SessionEntry e, int index) {
  final logs = workingLogs(e);
  logs[index] = logs[index].copyWith(done: !logs[index].done);
  return e.copyWith(logs: logs);
}

/// Ändert Wiederholungen und/oder Gewicht von Satz [index]. Bei einem
/// offenen Satz wird die Änderung in spätere, noch offene Sätze mit dem
/// bisherigen Wert übernommen – so muss ein anderes Gewicht nur einmal
/// eingestellt werden.
SessionEntry changeSet(
  SessionEntry e,
  int index, {
  int? Function()? reps,
  double? Function()? weightKg,
}) {
  final logs = workingLogs(e);
  final old = logs[index];
  final updated = old.copyWith(reps: reps, weightKg: weightKg);
  logs[index] = updated;
  // Die Korrektur eines bereits erledigten Satzes betrifft nur diesen Satz.
  if (old.done) return e.copyWith(logs: logs);
  for (var j = index + 1; j < logs.length; j++) {
    final l = logs[j];
    if (l.done) continue;
    logs[j] = l.copyWith(
      reps: reps != null && l.reps == old.reps ? () => updated.reps : null,
      weightKg: weightKg != null && l.weightKg == old.weightKg
          ? () => updated.weightKg
          : null,
    );
  }
  return e.copyWith(logs: logs);
}

/// Hakt alle offenen Sätze mit ihren aktuellen Werten ab.
SessionEntry completeAll(SessionEntry e) =>
    e.copyWith(logs: [for (final l in workingLogs(e)) l.copyWith(done: true)]);

/// Zusätzlicher Satz mit den Werten des letzten Satzes.
SessionEntry addSet(SessionEntry e) {
  final logs = workingLogs(e);
  logs.add(SetLog(reps: logs.last.reps, weightKg: logs.last.weightKg));
  return e.copyWith(logs: logs);
}

/// Ein Zusatzsatz lässt sich wieder entfernen, solange er offen ist.
bool canRemoveLastSet(SessionEntry e) =>
    e.logs.length > e.sets && !e.logs.last.done;

SessionEntry removeLastSet(SessionEntry e) => canRemoveLastSet(e)
    ? e.copyWith(logs: e.logs.sublist(0, e.logs.length - 1))
    : e;
