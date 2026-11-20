import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media.dart';
import 'media_platform_web.dart' if (dart.library.io) 'media_platform_io.dart';
import 'models.dart';
import 'seed.dart';
import 'sync/remote_codec.dart';
import 'sync/sync_meta.dart';
import 'taxonomy.dart';
import 'util.dart';

export 'util.dart' show newId, dateOnly;

/// Zentraler App-Zustand. Daten liegen lokal auf dem Gerät
/// (SharedPreferences, ein JSON-Dokument; Bilder separat in [media]) und
/// werden – wenn ein Konto verbunden ist – mit dem Server abgeglichen.
/// Die App bleibt ohne Netz voll benutzbar.
class AppStore extends ChangeNotifier {
  AppStore({
    MediaStorage? mediaStorage,
    this.storageKey = defaultStorageKey,
    this.persist = true,
  }) : media = MediaLibrary(mediaStorage ?? createPlatformMediaStorage()) {
    media.onAdded = sync.mediaUploads.add;
  }

  static const defaultStorageKey = 'coachplan_data_v1';

  /// Schlüssel der lokalen Ablage (in Tests je Gerät verschieden).
  final String storageKey;

  /// Ohne Ablage auf dem Gerät (Demo-Modus): alles bleibt im Speicher.
  final bool persist;
  String get _backupKey => '${storageKey}_corrupt_backup';

  final MediaLibrary media;
  final SyncMeta sync = SyncMeta();

  /// Wird nach jeder lokalen Änderung gerufen (stößt den Abgleich an).
  VoidCallback? onLocalChange;

  final List<Athlete> _athletes = [];
  final List<Exercise> _exercises = [];
  final List<TrainingSession> _sessions = [];
  final List<VideoClip> _clips = [];

  /// Angemeldet als Athlet: nur eigene Einheiten, keine Bearbeitung.
  bool get isAthlete => sync.role == 'athlete';

  List<Athlete> get athletes =>
      [..._athletes]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Exercise> get exercises =>
      [..._exercises]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<TrainingSession> get sessions => List.unmodifiable(_sessions);

  /// Neueste zuerst.
  List<VideoClip> get clips =>
      [..._clips]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) {
      _seedLibrary();
      await _save();
    } else {
      try {
        _fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        // Unlesbare Daten nicht verwerfen, sondern sichern und neu starten.
        await prefs.setString(_backupKey, raw);
        _clearData();
        _seedLibrary();
      }
    }
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'athletes': _athletes.map((e) => e.toJson()).toList(),
    'exercises': _exercises.map((e) => e.toJson()).toList(),
    'sessions': _sessions.map((e) => e.toJson()).toList(),
    'clips': _clips.map((e) => e.toJson()).toList(),
    'sync': sync.toJson(),
  };

  void _fromJson(Map<String, dynamic> j) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? const [])
            .map((e) => f(Map<String, dynamic>.from(e as Map)))
            .toList();
    final a = parse('athletes', Athlete.fromJson);
    final e = parse('exercises', Exercise.fromJson);
    final s = parse('sessions', TrainingSession.fromJson);
    final c = parse('clips', VideoClip.fromJson);
    _athletes
      ..clear()
      ..addAll(a);
    _exercises
      ..clear()
      ..addAll(e);
    _sessions
      ..clear()
      ..addAll(s);
    _clips
      ..clear()
      ..addAll(c);
    final meta = j['sync'];
    if (meta is Map) {
      sync.loadJson(Map<String, dynamic>.from(meta));
    } else {
      // Daten aus einer Version ohne Abgleich: alles gilt als neu.
      _markAllDirty();
    }
  }

  Future<void> _save() async {
    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(toJson()));
  }

  /// Speichert nur die Abgleich-Daten mit (nach einem Sync-Schritt).
  Future<void> saveSyncMeta() => _save();

  void _commit({bool local = true}) {
    notifyListeners();
    _save();
    if (local) onLocalChange?.call();
  }

  void _seedLibrary() {
    for (final e in seedExercises()) {
      _exercises.add(e);
      sync.markDirty('exercises', e.id);
    }
  }

  void _markAllDirty() {
    for (final a in _athletes) {
      sync.markDirty('athletes', a.id);
    }
    for (final e in _exercises) {
      sync.markDirty('exercises', e.id);
      sync.mediaUploads.addAll(e.imageIds);
    }
    for (final c in _clips) {
      sync.markDirty('clips', c.id);
      sync.mediaUploads.addAll(c.imageIds);
    }
    for (final s in _sessions) {
      sync.markDirty('sessionPlans', s.id);
      sync.markDirty('sessionLogs', s.id);
    }
  }

  void _clearData() {
    final images = _mediaInUse();
    _athletes.clear();
    _exercises.clear();
    _sessions.clear();
    _clips.clear();
    sync.clearPending();
    for (final id in images) {
      media.remove(id);
    }
  }

  // ---- Konto / Workspace --------------------------------------------------

  /// Bindet die lokalen Daten an ein Konto.
  ///
  /// Ein Trainer, der die App bisher ohne Konto genutzt hat, behält seine
  /// Daten (sie werden beim ersten Abgleich hochgeladen). In allen anderen
  /// Fällen mit anderem Konto wird der lokale Stand verworfen und vom
  /// Server neu geladen.
  void bindWorkspace({
    required String? workspace,
    required String role,
    String? athleteId,
  }) {
    final wasAthlete = sync.role == 'athlete';
    final bool keep;
    if (role == 'coach') {
      keep =
          !wasAthlete &&
          (sync.workspace == null || sync.workspace == workspace);
    } else {
      keep = wasAthlete && workspace != null && sync.workspace == workspace;
    }
    if (!keep) _clearData();
    if (sync.workspace != workspace) sync.cursors.clear();
    sync
      ..workspace = workspace
      ..role = role
      ..athleteId = athleteId;
    _commit(local: false);
  }

  /// Abmelden: Der Trainer behält seine Daten auf dem Gerät, beim Athleten
  /// werden die Daten des Trainers entfernt.
  void handleSignOut() {
    if (isAthlete) {
      _clearData();
      sync.workspace = null;
      _seedLibrary();
    }
    sync
      ..role = null
      ..athleteId = null;
    _commit(local: false);
  }

  /// Nach dem ersten Laden eines leeren Trainer-Kontos: Startbibliothek.
  void seedLibraryIfEmpty() {
    if (_exercises.isNotEmpty) return;
    _seedLibrary();
    _commit();
  }

  // ---- Abgleich: Daten für den Server ------------------------------------

  /// JSON-Inhalt eines Objekts für die Server-Tabelle [table].
  Map<String, dynamic>? remoteData(String table, String id) => switch (table) {
    'athletes' => switch (athleteById(id)) {
      final a? => athleteData(a),
      null => null,
    },
    'exercises' => switch (exerciseById(id)) {
      final e? => exerciseData(e),
      null => null,
    },
    'clips' => switch (clipById(id)) {
      final c? => clipData(c),
      null => null,
    },
    _ => null,
  };

  /// Übernimmt Zeilen vom Server. Lokal noch nicht hochgeladene Änderungen
  /// haben Vorrang – außer bei [remoteWins] (erster Abgleich eines Geräts).
  void applyRemote(
    String table,
    List<Map<String, dynamic>> rows, {
    bool remoteWins = false,
  }) {
    if (rows.isEmpty) return;
    final releasable = <String>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final deleted = row['deleted'] == true;
      if (table == 'sessions') {
        _applyRemoteSession(row, id, deleted, remoteWins);
        continue;
      }
      if (remoteWins) {
        sync.forget(table, id);
      } else if (sync.hasLocalChange(table, id)) {
        continue;
      }
      final data = Map<String, dynamic>.from(row['data'] as Map? ?? const {});
      data['id'] = id;
      switch (table) {
        case 'athletes':
          _athletes.removeWhere((a) => a.id == id);
          if (!deleted) _athletes.add(Athlete.fromJson(data));
        case 'exercises':
          releasable.addAll(exerciseById(id)?.imageIds ?? const []);
          _exercises.removeWhere((e) => e.id == id);
          if (!deleted) _exercises.add(Exercise.fromJson(data));
        case 'clips':
          releasable.addAll(clipById(id)?.imageIds ?? const []);
          _clips.removeWhere((c) => c.id == id);
          if (!deleted) _clips.add(VideoClip.fromJson(data));
      }
    }
    _releaseLocalMedia(releasable);
    notifyListeners();
    _save();
  }

  void _applyRemoteSession(
    Map<String, dynamic> row,
    String id,
    bool deleted,
    bool remoteWins,
  ) {
    if (remoteWins) sync.forget('sessions', id);
    if (sync.deleted['sessions']!.contains(id)) return;
    final local = sessionById(id);
    if (deleted) {
      sync.forget('sessions', id);
      _sessions.removeWhere((s) => s.id == id);
      return;
    }
    final keepPlan = local != null && sync.dirty['sessionPlans']!.contains(id);
    final keepLog = local != null && sync.dirty['sessionLogs']!.contains(id);
    final merged = sessionFromRemote(
      id: id,
      athleteId: keepPlan ? local.athleteId : row['athlete_id'] as String,
      plan: keepPlan ? sessionPlan(local) : row['data'],
      log: keepLog ? sessionLog(local) : row['log'],
    );
    final i = _sessions.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _sessions[i] = merged;
    } else {
      _sessions.add(merged);
    }
  }

  /// Entfernt lokale Einheiten, die es am Server für dieses Konto nicht
  /// (mehr) gibt. Nur für die Athleten-Sicht.
  void retainSessions(Set<String> remoteIds) {
    final before = _sessions.length;
    _sessions.removeWhere((s) {
      final gone = !remoteIds.contains(s.id);
      if (gone) sync.forget('sessions', s.id);
      return gone;
    });
    if (_sessions.length != before) {
      notifyListeners();
      _save();
    }
  }

  // ---- Bilder -------------------------------------------------------------

  Set<String> _mediaInUse() => {
    for (final e in _exercises) ...e.imageIds,
    for (final c in _clips) ...c.imageIds,
  };

  /// Löscht die genannten Bilder, sofern keine Übung und kein Clip sie mehr
  /// verwendet. Nach jedem Entfernen/Verwerfen von Bildern aufrufen.
  void releaseMedia(Iterable<String> ids) {
    final candidates = ids.toSet();
    if (candidates.isEmpty) return;
    final used = _mediaInUse();
    for (final id in candidates) {
      if (used.contains(id)) continue;
      media.remove(id);
      // Noch nicht hochgeladen → nichts zu löschen; sonst auch am Server.
      if (!sync.mediaUploads.remove(id)) sync.mediaDeletes.add(id);
    }
  }

  /// Wie [releaseMedia], aber ohne Löschauftrag an den Server (die Änderung
  /// kam von dort).
  void _releaseLocalMedia(Iterable<String> ids) {
    final candidates = ids.toSet();
    if (candidates.isEmpty) return;
    final used = _mediaInUse();
    for (final id in candidates) {
      if (used.contains(id)) continue;
      media.remove(id);
      sync.mediaUploads.remove(id);
    }
  }

  // ---- Athleten -----------------------------------------------------------

  Athlete? athleteById(String id) {
    for (final a in _athletes) {
      if (a.id == id) return a;
    }
    return null;
  }

  void upsertAthlete(Athlete athlete) {
    final i = _athletes.indexWhere((a) => a.id == athlete.id);
    if (i >= 0) {
      _athletes[i] = athlete;
    } else {
      _athletes.add(athlete);
    }
    sync.markDirty('athletes', athlete.id);
    _commit();
  }

  /// Löscht den Athleten inklusive aller seiner Einheiten.
  void deleteAthlete(String id) {
    _athletes.removeWhere((a) => a.id == id);
    sync.markDeleted('athletes', id);
    for (final s in sessionsFor(id)) {
      sync.markDeleted('sessions', s.id);
    }
    _sessions.removeWhere((s) => s.athleteId == id);
    _commit();
  }

  // ---- Übungen ------------------------------------------------------------

  Exercise? exerciseById(String id) {
    for (final e in _exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  void upsertExercise(Exercise exercise) {
    final i = _exercises.indexWhere((e) => e.id == exercise.id);
    final previous = i >= 0 ? _exercises[i].imageIds : const <String>[];
    if (i >= 0) {
      _exercises[i] = exercise;
    } else {
      _exercises.add(exercise);
    }
    sync.markDirty('exercises', exercise.id);
    releaseMedia(previous);
    _commit();
  }

  void deleteExercise(String id) {
    final previous = exerciseById(id)?.imageIds ?? const <String>[];
    _exercises.removeWhere((e) => e.id == id);
    sync.markDeleted('exercises', id);
    releaseMedia(previous);
    _commit();
  }

  /// Baukasten "Ziel": Vorbelegung plus alle selbst vergebenen Schlagworte.
  List<String> get goalVocabulary =>
      mergeVocabulary(defaultGoals, _exercises.expand((e) => e.goals));

  /// Baukasten "Equipment".
  List<String> get equipmentVocabulary =>
      mergeVocabulary(defaultEquipment, _exercises.expand((e) => e.equipment));

  // ---- Clips --------------------------------------------------------------

  VideoClip? clipById(String? id) {
    if (id == null) return null;
    for (final c in _clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Exercise> exercisesFromClip(String clipId) =>
      exercises.where((e) => e.sourceClipId == clipId).toList();

  void upsertClip(VideoClip clip) {
    final i = _clips.indexWhere((c) => c.id == clip.id);
    final previous = i >= 0 ? _clips[i].imageIds : const <String>[];
    if (i >= 0) {
      _clips[i] = clip;
    } else {
      _clips.add(clip);
    }
    sync.markDirty('clips', clip.id);
    releaseMedia(previous);
    _commit();
  }

  /// Entfernt den Clip; daraus abgeleitete Übungen bleiben bestehen.
  void deleteClip(String id) {
    final previous = clipById(id)?.imageIds ?? const <String>[];
    _clips.removeWhere((c) => c.id == id);
    sync.markDeleted('clips', id);
    releaseMedia(previous);
    _commit();
  }

  // ---- Einheiten ----------------------------------------------------------

  TrainingSession? sessionById(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<TrainingSession> sessionsFor(String athleteId) =>
      _sessions.where((s) => s.athleteId == athleteId).toList();

  /// Einheiten ab heute, aufsteigend nach Datum.
  List<TrainingSession> upcoming({String? athleteId, DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    return _sessions
        .where(
          (s) =>
              !dateOnly(s.date).isBefore(today) &&
              (athleteId == null || s.athleteId == athleteId),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Einheiten vor heute, neueste zuerst.
  List<TrainingSession> past({String? athleteId, DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    return _sessions
        .where(
          (s) =>
              dateOnly(s.date).isBefore(today) &&
              (athleteId == null || s.athleteId == athleteId),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  void upsertSession(TrainingSession session) {
    final i = _sessions.indexWhere((s) => s.id == session.id);
    if (i >= 0) {
      final old = _sessions[i];
      // Plan und Protokoll getrennt verfolgen: so überschreibt der Trainer
      // beim Umplanen nicht das, was der Athlet gerade abhakt.
      if (old.athleteId != session.athleteId ||
          jsonEncode(sessionPlan(old)) != jsonEncode(sessionPlan(session))) {
        sync.markDirty('sessionPlans', session.id);
      }
      if (jsonEncode(sessionLog(old)) != jsonEncode(sessionLog(session))) {
        sync.markDirty('sessionLogs', session.id);
      }
      _sessions[i] = session;
    } else {
      sync.markDirty('sessionPlans', session.id);
      sync.markDirty('sessionLogs', session.id);
      _sessions.add(session);
    }
    _commit();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    sync.markDeleted('sessions', id);
    _commit();
  }

  void setDone(String id, bool done) {
    final s = sessionById(id);
    if (s == null) return;
    upsertSession(s.copyWith(done: done));
  }

  /// Ersetzt eine Übung der Einheit (z. B. nach dem Abhaken eines Satzes).
  void updateEntry(String sessionId, SessionEntry entry) {
    final s = sessionById(sessionId);
    if (s == null) return;
    upsertSession(
      s.copyWith(
        entries: [for (final e in s.entries) e.id == entry.id ? entry : e],
      ),
    );
  }

  /// Kopiert eine Einheit auf einen (anderen) Athleten und ein neues Datum.
  /// Die Kopie ist offen und enthält keine protokollierten Sätze.
  TrainingSession duplicateSession(
    TrainingSession source, {
    required String athleteId,
    required DateTime date,
  }) {
    final copy = source.copyWith(
      id: newId(),
      athleteId: athleteId,
      date: dateOnly(date),
      done: false,
      rpe: () => null,
      feedback: '',
      entries: [
        for (final e in source.entries) e.copyWith(id: newId(), logs: const []),
      ],
    );
    upsertSession(copy);
    return copy;
  }
}

/// Stellt den [AppStore] im Widget-Baum bereit; Widgets, die [of] nutzen,
/// werden bei Änderungen neu gebaut.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
