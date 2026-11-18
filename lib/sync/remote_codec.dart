import '../models.dart';

/// Übersetzt zwischen App-Objekten und den Zeilen der Server-Tabellen.
///
/// Eine Einheit liegt auf dem Server in zwei Teilen: dem Plan des Trainers
/// ("data") und dem Protokoll des Athleten ("log"). So überschreiben sich
/// Trainer und Athlet nicht gegenseitig.

Map<String, dynamic> _withoutId(Map<String, dynamic> json) =>
    {...json}..remove('id');

Map<String, dynamic> athleteData(Athlete a) => _withoutId(a.toJson());
Map<String, dynamic> exerciseData(Exercise e) => _withoutId(e.toJson());
Map<String, dynamic> clipData(VideoClip c) => _withoutId(c.toJson());

Map<String, dynamic> sessionPlan(TrainingSession s) => {
  'title': s.title,
  'date': s.date.toIso8601String(),
  'notes': s.notes,
  'entries': [for (final e in s.entries) e.toJson()..remove('logs')],
};

Map<String, dynamic> sessionLog(TrainingSession s) => {
  'done': s.done,
  'rpe': s.rpe,
  'feedback': s.feedback,
  'logs': {
    for (final e in s.entries)
      if (e.logs.isNotEmpty) e.id: [for (final l in e.logs) l.toJson()],
  },
};

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

TrainingSession sessionFromRemote({
  required String id,
  required String athleteId,
  required Object? plan,
  required Object? log,
}) {
  final p = _map(plan);
  final l = _map(log);
  final logs = _map(l['logs']);
  final base = TrainingSession.fromJson({
    ...p,
    'id': id,
    'athleteId': athleteId,
    'done': l['done'] ?? false,
    'rpe': l['rpe'],
    'feedback': l['feedback'] ?? '',
  });
  return base.copyWith(
    entries: [
      for (final e in base.entries)
        e.copyWith(
          logs: [
            for (final raw in (logs[e.id] as List?) ?? const [])
              SetLog.fromJson(Map<String, dynamic>.from(raw as Map)),
          ],
        ),
    ],
  );
}
