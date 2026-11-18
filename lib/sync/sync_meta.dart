/// Was dieses Gerät noch mit dem Server abgleichen muss und bis wohin es
/// den Serverstand schon kennt. Wird zusammen mit den Daten gespeichert.
class SyncMeta {
  /// Trainer-Konto (coach_id), zu dem die lokalen Daten gehören.
  /// `null` = rein lokale Daten ohne Konto.
  String? workspace;

  /// "coach", "athlete" oder `null` (nicht angemeldet → Trainer-Ansicht).
  String? role;

  /// Eigene Athleten-ID im Workspace (nur Rolle "athlete").
  String? athleteId;

  static const dirtyKinds = [
    'athletes',
    'exercises',
    'clips',
    'sessionPlans',
    'sessionLogs',
  ];
  static const tables = ['athletes', 'exercises', 'clips', 'sessions'];

  /// Lokal geänderte Objekte je Art.
  final Map<String, Set<String>> dirty = {
    for (final k in dirtyKinds) k: <String>{},
  };

  /// Lokal gelöschte Objekte je Tabelle.
  final Map<String, Set<String>> deleted = {
    for (final t in tables) t: <String>{},
  };

  /// Bilder, die noch hoch- bzw. auf dem Server gelöscht werden müssen.
  final Set<String> mediaUploads = {};
  final Set<String> mediaDeletes = {};

  /// Letzter bekannter Änderungszeitpunkt je Tabelle (Serverzeit).
  final Map<String, String> cursors = {};

  static String _tableOf(String kind) =>
      kind.startsWith('session') ? 'sessions' : kind;

  void markDirty(String kind, String id) {
    dirty[kind]!.add(id);
    deleted[_tableOf(kind)]!.remove(id);
  }

  void markDeleted(String table, String id) {
    for (final kind in dirtyKinds) {
      if (_tableOf(kind) == table) dirty[kind]!.remove(id);
    }
    deleted[table]!.add(id);
  }

  /// Vergisst alle offenen Änderungen an diesem Objekt (Serverstand gilt).
  void forget(String table, String id) {
    for (final kind in dirtyKinds) {
      if (_tableOf(kind) == table) dirty[kind]!.remove(id);
    }
    deleted[table]!.remove(id);
  }

  bool hasLocalChange(String table, String id) =>
      deleted[table]!.contains(id) ||
      dirtyKinds.any((k) => _tableOf(k) == table && dirty[k]!.contains(id));

  /// Entnimmt die offenen IDs; bei einem Fehler mit [restoreDirty] zurück.
  Set<String> takeDirty(String kind) {
    final ids = {...dirty[kind]!};
    dirty[kind]!.clear();
    return ids;
  }

  Set<String> takeDeleted(String table) {
    final ids = {...deleted[table]!};
    deleted[table]!.clear();
    return ids;
  }

  void restoreDirty(String kind, Iterable<String> ids) {
    // Inzwischen gelöschte Objekte nicht wieder als geändert führen.
    final gone = deleted[_tableOf(kind)]!;
    dirty[kind]!.addAll(ids.where((id) => !gone.contains(id)));
  }

  void restoreDeleted(String table, Iterable<String> ids) =>
      deleted[table]!.addAll(ids);

  int get pendingCount {
    var n = mediaUploads.length + mediaDeletes.length;
    for (final set in dirty.values) {
      n += set.length;
    }
    for (final set in deleted.values) {
      n += set.length;
    }
    return n;
  }

  void clearPending() {
    for (final s in dirty.values) {
      s.clear();
    }
    for (final s in deleted.values) {
      s.clear();
    }
    mediaUploads.clear();
    mediaDeletes.clear();
    cursors.clear();
  }

  Map<String, dynamic> toJson() => {
    'workspace': workspace,
    'role': role,
    'athleteId': athleteId,
    'dirty': {for (final e in dirty.entries) e.key: e.value.toList()},
    'deleted': {for (final e in deleted.entries) e.key: e.value.toList()},
    'mediaUploads': mediaUploads.toList(),
    'mediaDeletes': mediaDeletes.toList(),
    'cursors': cursors,
  };

  void loadJson(Map<String, dynamic> j) {
    Iterable<String> list(Object? v) =>
        ((v as List?) ?? const []).map((e) => '$e');
    workspace = j['workspace'] as String?;
    role = j['role'] as String?;
    athleteId = j['athleteId'] as String?;
    clearPending();
    final d = (j['dirty'] as Map?) ?? const {};
    for (final k in dirtyKinds) {
      dirty[k]!.addAll(list(d[k]));
    }
    final del = (j['deleted'] as Map?) ?? const {};
    for (final t in tables) {
      deleted[t]!.addAll(list(del[t]));
    }
    mediaUploads.addAll(list(j['mediaUploads']));
    mediaDeletes.addAll(list(j['mediaDeletes']));
    ((j['cursors'] as Map?) ?? const {}).forEach(
      (k, v) => cursors['$k'] = '$v',
    );
  }
}
