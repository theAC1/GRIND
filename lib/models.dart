import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

enum ExerciseCategory {
  kraft('Kraft', Icons.fitness_center),
  physio('Physio', Icons.healing),
  mobility('Mobility', Icons.self_improvement);

  const ExerciseCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  static ExerciseCategory fromName(String? name) => values.firstWhere(
    (c) => c.name == name,
    orElse: () => ExerciseCategory.kraft,
  );
}

List<String> _strings(Object? v) =>
    ((v as List?) ?? const []).map((e) => '$e').toList();

class Athlete {
  Athlete({
    required this.id,
    required this.name,
    this.sport = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final String sport;
  final String notes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sport': sport,
    'notes': notes,
  };

  factory Athlete.fromJson(Map<String, dynamic> j) => Athlete(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    sport: j['sport'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
  );
}

class Exercise {
  Exercise({
    required this.id,
    required this.name,
    required this.category,
    this.bodyRegion = '',
    this.description = '',
    this.whenToUse = '',
    this.goals = const [],
    this.equipment = const [],
    this.videoLinks = const [],
    this.imageIds = const [],
    this.sourceClipId,
    this.needsReview = false,
  });

  final String id;
  final String name;
  final ExerciseCategory category;
  final String bodyRegion;

  /// Coach-Hinweise zur Ausführung.
  final String description;

  /// Wann/wofür die Übung eingesetzt wird.
  final String whenToUse;

  /// Baukasten-Tags, z. B. "Maximalkraft", "Reha".
  final List<String> goals;

  /// Baukasten-Tags, z. B. "Langhantel", "Band".
  final List<String> equipment;

  /// Links zu YouTube, Instagram usw.
  final List<String> videoLinks;

  /// IDs gespeicherter Bilder (siehe MediaLibrary).
  final List<String> imageIds;

  /// Clip, aus dem die Übung abgeleitet wurde.
  final String? sourceClipId;

  /// Automatisch importiert und vom Trainer noch nicht geprüft. Wird beim
  /// Speichern im Editor zurückgesetzt.
  final bool needsReview;

  bool get hasMedia => videoLinks.isNotEmpty || imageIds.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'bodyRegion': bodyRegion,
    'description': description,
    'whenToUse': whenToUse,
    'goals': goals,
    'equipment': equipment,
    'videoLinks': videoLinks,
    'imageIds': imageIds,
    'sourceClipId': sourceClipId,
    if (needsReview) 'needsReview': true,
  };

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final links = _strings(j['videoLinks']);
    // Altes Format (v1): ein einzelnes Feld "videoUrl".
    final legacy = (j['videoUrl'] as String? ?? '').trim();
    if (legacy.isNotEmpty && !links.contains(legacy)) links.add(legacy);
    return Exercise(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      category: ExerciseCategory.fromName(j['category'] as String?),
      bodyRegion: j['bodyRegion'] as String? ?? '',
      description: j['description'] as String? ?? '',
      whenToUse: j['whenToUse'] as String? ?? '',
      goals: _strings(j['goals']),
      equipment: _strings(j['equipment']),
      videoLinks: links,
      imageIds: _strings(j['imageIds']),
      sourceClipId: j['sourceClipId'] as String?,
      needsReview: j['needsReview'] == true,
    );
  }
}

/// Gespeicherter Link (Reel, Short, Video) als Rohmaterial für Übungen.
class VideoClip {
  VideoClip({
    required this.id,
    required this.url,
    this.title = '',
    this.notes = '',
    this.imageIds = const [],
    required this.createdAt,
  });

  final String id;
  final String url;
  final String title;

  /// Notizen oder eingefügtes Transkript / Bildunterschrift.
  final String notes;
  final List<String> imageIds;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'notes': notes,
    'imageIds': imageIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory VideoClip.fromJson(Map<String, dynamic> j) => VideoClip(
    id: j['id'] as String,
    url: j['url'] as String? ?? '',
    title: j['title'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    imageIds: _strings(j['imageIds']),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Ein tatsächlich absolvierter (oder noch offener) Satz.
class SetLog {
  const SetLog({this.reps, this.weightKg, this.done = false});

  /// Wiederholungen bzw. Dauer – Einheit ergibt sich aus der Vorgabe.
  final int? reps;
  final double? weightKg;
  final bool done;

  SetLog copyWith({
    int? Function()? reps,
    double? Function()? weightKg,
    bool? done,
  }) => SetLog(
    reps: reps != null ? reps() : this.reps,
    weightKg: weightKg != null ? weightKg() : this.weightKg,
    done: done ?? this.done,
  );

  Map<String, dynamic> toJson() => {
    'reps': reps,
    'weightKg': weightKg,
    'done': done,
  };

  factory SetLog.fromJson(Map<String, dynamic> j) => SetLog(
    reps: (j['reps'] as num?)?.toInt(),
    weightKg: (j['weightKg'] as num?)?.toDouble(),
    done: j['done'] as bool? ?? false,
  );
}

/// Eine Übung innerhalb einer Trainingseinheit: Vorgabe des Trainers plus
/// die vom Athleten protokollierten Sätze.
///
/// [name] und [category] werden als Kopie gespeichert, damit ein Plan lesbar
/// bleibt, auch wenn die Übung später aus der Bibliothek gelöscht wird.
class SessionEntry {
  SessionEntry({
    required this.id,
    required this.exerciseId,
    required this.name,
    required this.category,
    this.sets = 3,
    this.reps = '10',
    this.weightKg,
    this.load = '',
    this.restSec,
    this.note = '',
    this.logs = const [],
  });

  final String id;
  final String exerciseId;
  final String name;
  final ExerciseCategory category;
  final int sets;

  /// Freitext: "10", "8–12" oder "30 s".
  final String reps;

  /// Vorgegebenes Gewicht; `null` = ohne Zusatzgewicht.
  final double? weightKg;

  /// Freitext für Widerstand/Gerät: "rotes Theraband", "Körpergewicht".
  final String load;
  final int? restSec;

  /// Coach-Hinweis speziell für diese Einheit.
  final String note;
  final List<SetLog> logs;

  int get plannedSetCount => math.max(sets, logs.length);
  int get doneSetCount => logs.where((l) => l.done).length;
  bool get isComplete => doneSetCount >= plannedSetCount;

  SessionEntry copyWith({
    String? id,
    int? sets,
    String? reps,
    double? Function()? weightKg,
    String? load,
    int? Function()? restSec,
    String? note,
    List<SetLog>? logs,
  }) => SessionEntry(
    id: id ?? this.id,
    exerciseId: exerciseId,
    name: name,
    category: category,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    weightKg: weightKg != null ? weightKg() : this.weightKg,
    load: load ?? this.load,
    restSec: restSec != null ? restSec() : this.restSec,
    note: note ?? this.note,
    logs: logs ?? this.logs,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'name': name,
    'category': category.name,
    'sets': sets,
    'reps': reps,
    'weightKg': weightKg,
    'load': load,
    'restSec': restSec,
    'note': note,
    'logs': logs.map((l) => l.toJson()).toList(),
  };

  factory SessionEntry.fromJson(Map<String, dynamic> j) {
    var weight = (j['weightKg'] as num?)?.toDouble();
    var load = j['load'] as String? ?? '';
    // Altes Format (v1): Gewicht stand als Text in "load", z. B. "60 kg".
    if (weight == null) {
      final m = RegExp(
        r'^\s*(\d+(?:[.,]\d+)?)\s*kg\s*$',
        caseSensitive: false,
      ).firstMatch(load);
      if (m != null) {
        weight = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        if (weight != null) load = '';
      }
    }
    return SessionEntry(
      id: j['id'] as String,
      exerciseId: j['exerciseId'] as String? ?? '',
      name: j['name'] as String? ?? '',
      category: ExerciseCategory.fromName(j['category'] as String?),
      sets: (j['sets'] as num?)?.toInt() ?? 1,
      reps: j['reps'] as String? ?? '',
      weightKg: weight,
      load: load,
      restSec: (j['restSec'] as num?)?.toInt(),
      note: j['note'] as String? ?? '',
      logs: ((j['logs'] as List?) ?? const [])
          .map((e) => SetLog.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class TrainingSession {
  TrainingSession({
    required this.id,
    required this.athleteId,
    required this.title,
    required this.date,
    this.notes = '',
    this.entries = const [],
    this.done = false,
    this.rpe,
    this.feedback = '',
  });

  final String id;
  final String athleteId;
  final String title;
  final DateTime date;
  final String notes;
  final List<SessionEntry> entries;
  final bool done;

  /// Subjektive Belastung 1–10, vom Athleten beim Abschließen gesetzt.
  final int? rpe;

  /// Rückmeldung des Athleten an den Trainer.
  final String feedback;

  int get totalSets => entries.fold(0, (sum, e) => sum + e.plannedSetCount);
  int get doneSets => entries.fold(0, (sum, e) => sum + e.doneSetCount);
  bool get started => doneSets > 0;

  /// Kategorie mit den meisten Übungen (für die Farbmarkierung).
  ExerciseCategory? get dominantCategory {
    if (entries.isEmpty) return null;
    final counts = <ExerciseCategory, int>{};
    for (final e in entries) {
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  TrainingSession copyWith({
    String? id,
    String? athleteId,
    String? title,
    DateTime? date,
    String? notes,
    List<SessionEntry>? entries,
    bool? done,
    int? Function()? rpe,
    String? feedback,
  }) => TrainingSession(
    id: id ?? this.id,
    athleteId: athleteId ?? this.athleteId,
    title: title ?? this.title,
    date: date ?? this.date,
    notes: notes ?? this.notes,
    entries: entries ?? this.entries,
    done: done ?? this.done,
    rpe: rpe != null ? rpe() : this.rpe,
    feedback: feedback ?? this.feedback,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'athleteId': athleteId,
    'title': title,
    'date': date.toIso8601String(),
    'notes': notes,
    'entries': entries.map((e) => e.toJson()).toList(),
    'done': done,
    'rpe': rpe,
    'feedback': feedback,
  };

  factory TrainingSession.fromJson(Map<String, dynamic> j) => TrainingSession(
    id: j['id'] as String,
    athleteId: j['athleteId'] as String? ?? '',
    title: j['title'] as String? ?? '',
    date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
    notes: j['notes'] as String? ?? '',
    entries: ((j['entries'] as List?) ?? const [])
        .map((e) => SessionEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    done: j['done'] as bool? ?? false,
    rpe: (j['rpe'] as num?)?.toInt(),
    feedback: j['feedback'] as String? ?? '',
  );
}
