import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

import '../store.dart';
import 'remote_codec.dart';

enum SyncStatus {
  /// Kein Server eingerichtet oder nicht angemeldet.
  off,
  idle,
  syncing,
  error,
}

/// Fehler mit einer Meldung, die man dem Nutzer zeigen kann.
class BackendException implements Exception {
  BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Stand der App-Verknüpfung eines Athleten (Sicht des Trainers).
class AthleteAccess {
  const AthleteAccess({required this.linked, this.code, this.expiresAt});

  final bool linked;
  final String? code;
  final DateTime? expiresAt;

  bool get hasValidCode =>
      code != null && expiresAt != null && expiresAt!.isAfter(DateTime.now());
}

/// Verbindung zum Supabase-Server: Anmeldung, Einladungen und der Abgleich
/// zwischen [AppStore] und Server.
///
/// Ablauf eines Abgleichs: erst lokale Änderungen hochladen, dann alles
/// laden, was sich seit dem letzten Mal am Server geändert hat. Beim
/// allerersten Abgleich eines Geräts gilt umgekehrt zuerst der Serverstand.
class Backend extends ChangeNotifier {
  Backend(this.store) {
    store.onLocalChange = schedule;
  }

  final AppStore store;

  String? url;
  String? anonKey;
  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSub;

  SyncStatus status = SyncStatus.off;
  String? lastError;
  DateTime? lastSync;

  Timer? _debounce;
  Timer? _poll;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  String get _urlKey => '${store.storageKey}_backend_url';
  String get _anonKeyKey => '${store.storageKey}_backend_key';
  String get _sessionKey => '${store.storageKey}_auth_session';

  bool get configured => _client != null;
  bool get signedIn => _client?.auth.currentSession != null;
  String? get email => _client?.auth.currentUser?.email;
  String? get role => store.sync.role;
  bool get linked => store.sync.workspace != null;

  // ---- Einrichtung --------------------------------------------------------

  /// Lädt die gespeicherte Server-Verbindung und Anmeldung.
  /// [defaultUrl]/[defaultKey] kommen aus dem Build (--dart-define).
  Future<void> init({String? defaultUrl, String? defaultKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final u = prefs.getString(_urlKey) ?? _nonEmpty(defaultUrl);
    final k = prefs.getString(_anonKeyKey) ?? _nonEmpty(defaultKey);
    if (u == null || k == null) return;
    _connect(u, k);
    final saved = prefs.getString(_sessionKey);
    if (saved != null) {
      try {
        await _client!.auth.recoverSession(saved);
      } catch (_) {
        // Offline oder Sitzung abgelaufen: lokal weiterarbeiten, der
        // nächste Abgleich versucht es erneut.
      }
    }
    _setStatus(signedIn ? SyncStatus.idle : SyncStatus.off);
    if (signedIn) unawaited(sync());
  }

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  void _connect(String u, String k) {
    _authSub?.cancel();
    _client?.dispose();
    url = u;
    anonKey = k;
    final client = SupabaseClient(
      u,
      k,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    _client = client;
    _authSub = client.auth.onAuthStateChange.listen((state) async {
      final prefs = await SharedPreferences.getInstance();
      final session = state.session;
      if (session == null) {
        await prefs.remove(_sessionKey);
      } else {
        await prefs.setString(_sessionKey, _encodeSession(session));
      }
    });
    store.media.remoteFetch = _fetchImage;
  }

  // recoverSession erwartet genau dieses JSON.
  static String _encodeSession(Session s) => jsonEncode(s.toJson());

  /// Prüft Adresse und Schlüssel und speichert die Verbindung.
  Future<void> configure(String serverUrl, String key) async {
    var u = serverUrl.trim();
    final k = key.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    final uri = Uri.tryParse(u);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw BackendException('Bitte eine vollständige Adresse eingeben.');
    }
    if (k.isEmpty) throw BackendException('Der API-Schlüssel fehlt.');

    final probe = SupabaseClient(
      u,
      k,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: false,
      ),
    );
    try {
      await probe.from('profiles').select('id').limit(1);
    } on PostgrestException catch (e) {
      // "permission denied" ist die erwartete Antwort für nicht angemeldete
      // Zugriffe – der Server ist da und die Tabellen existieren.
      if (e.code != '42501') {
        if (e.code == 'PGRST205' || e.code == '42P01') {
          throw BackendException(
            'Server erreichbar, aber die CoachPlan-Tabellen fehlen '
            '(Migration nicht eingespielt).',
          );
        }
        throw BackendException(
          'Der Server hat die Anfrage abgelehnt – stimmt der API-Schlüssel?',
        );
      }
    } catch (e) {
      throw BackendException(friendlyError(e));
    } finally {
      await probe.dispose();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, u);
    await prefs.setString(_anonKeyKey, k);
    _connect(u, k);
    _setStatus(SyncStatus.off);
  }

  /// Trennt die Verbindung zum Server (meldet vorher ab).
  Future<void> disconnect() async {
    if (signedIn) await signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_anonKeyKey);
    await prefs.remove(_sessionKey);
    await _authSub?.cancel();
    await _client?.dispose();
    _client = null;
    url = null;
    anonKey = null;
    store.media.remoteFetch = null;
    _setStatus(SyncStatus.off);
  }

  /// Gleicht regelmäßig ab, damit z. B. der Trainer das Protokoll des
  /// Athleten ohne eigenes Zutun sieht.
  void startAutoSync({Duration every = const Duration(seconds: 45)}) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) {
      if (signedIn && linked) sync();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _poll?.cancel();
    _authSub?.cancel();
    _client?.dispose();
    if (store.onLocalChange == schedule) store.onLocalChange = null;
    super.dispose();
  }

  void _setStatus(SyncStatus s, {String? error}) {
    status = s;
    lastError = error;
    if (!_disposed) notifyListeners();
  }

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw BackendException('Kein Server eingerichtet.');
    return c;
  }

  // ---- Anmeldung ----------------------------------------------------------

  Future<void> signUp({
    required String email,
    required String password,
    required String role,
    required String name,
  }) async {
    try {
      final res = await _c.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'role': role, 'display_name': name.trim()},
      );
      if (res.session == null) {
        throw BackendException(
          'Konto angelegt. Bitte die E-Mail bestätigen und dann anmelden.',
        );
      }
    } on BackendException {
      rethrow;
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
    await _afterSignIn();
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _c.auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
    await _afterSignIn();
  }

  Future<void> _afterSignIn() async {
    try {
      await _bind();
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
    _setStatus(SyncStatus.idle);
    await sync();
  }

  Future<void> signOut() async {
    _debounce?.cancel();
    try {
      await _c.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Auch offline abmelden können.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    store.handleSignOut();
    lastSync = null;
    _setStatus(SyncStatus.off);
  }

  /// Ermittelt Rolle und Workspace des angemeldeten Kontos.
  Future<void> _bind() async {
    final uid = _c.auth.currentUser!.id;
    final profile = await _c
        .from('profiles')
        .select('role')
        .eq('id', uid)
        .maybeSingle();
    final role = (profile?['role'] as String?) ?? 'athlete';
    if (role == 'coach') {
      store.bindWorkspace(workspace: uid, role: 'coach');
      return;
    }
    final link = await _c
        .from('athletes')
        .select('coach_id,id')
        .eq('user_id', uid)
        .eq('deleted', false)
        .limit(1)
        .maybeSingle();
    store.bindWorkspace(
      workspace: link?['coach_id'] as String?,
      role: 'athlete',
      athleteId: link?['id'] as String?,
    );
  }

  // ---- Einladungen --------------------------------------------------------

  /// Trainer: Stand der Verknüpfung eines Athleten.
  Future<AthleteAccess> athleteAccess(String athleteId) async {
    try {
      await sync();
      final row = await _c
          .from('athletes')
          .select('user_id,invite_code,invite_expires_at')
          .eq('coach_id', store.sync.workspace!)
          .eq('id', athleteId)
          .maybeSingle();
      return AthleteAccess(
        linked: row?['user_id'] != null,
        code: row?['invite_code'] as String?,
        expiresAt: DateTime.tryParse(row?['invite_expires_at'] as String? ?? '')
            ?.toLocal(),
      );
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
  }

  /// Trainer: neuer Einladungscode (7 Tage gültig).
  Future<String> createInvite(String athleteId) async {
    try {
      await sync(); // der Athlet muss am Server existieren
      final code = await _c.rpc(
        'create_invite',
        params: {'p_athlete_id': athleteId},
      );
      return code as String;
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
  }

  /// Trainer: nimmt dem Athleten den App-Zugang wieder.
  Future<void> unlinkAthlete(String athleteId) async {
    try {
      await _c
          .from('athletes')
          .update({
            'user_id': null,
            'invite_code': null,
            'invite_expires_at': null,
          })
          .eq('coach_id', store.sync.workspace!)
          .eq('id', athleteId);
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
  }

  /// Athlet: verknüpft das eigene Konto mit dem Eintrag beim Trainer.
  Future<void> redeemInvite(String code) async {
    try {
      await _c.rpc('redeem_invite', params: {'p_code': code});
      await _bind();
    } catch (e) {
      throw BackendException(friendlyError(e));
    }
    await sync();
  }

  // ---- Abgleich -----------------------------------------------------------

  /// Stößt einen Abgleich kurz nach der letzten lokalen Änderung an.
  void schedule() {
    if (!configured || _disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), sync);
  }

  /// Gleicht jetzt ab. Wirft nicht; Fehler stehen in [status]/[lastError].
  Future<void> sync() async {
    if (_disposed || !configured) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _debounce?.cancel();
    try {
      await _ensureSession();
      if (!signedIn) {
        _setStatus(SyncStatus.off);
        return;
      }
      _setStatus(SyncStatus.syncing);
      if (store.sync.role != 'coach' || !linked) {
        // Verknüpfung kann sich geändert haben (eingeladen / entfernt).
        await _bind();
      }
      if (linked) {
        final first = store.sync.cursors.isEmpty;
        if (first) {
          await _pull(remoteWins: true);
          if (store.sync.role == 'coach') store.seedLibraryIfEmpty();
        }
        await _push();
        await _pull();
        await _syncMedia();
      }
      await store.saveSyncMeta();
      lastSync = DateTime.now();
      _setStatus(SyncStatus.idle);
    } catch (e) {
      await store.saveSyncMeta();
      _setStatus(SyncStatus.error, error: friendlyError(e));
    } finally {
      _running = false;
      if (_again && !_disposed) {
        _again = false;
        schedule();
      }
    }
  }

  Future<void> _ensureSession() async {
    if (signedIn) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sessionKey);
    if (saved != null) await _c.auth.recoverSession(saved);
  }

  static const _batch = 200;

  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    for (var i = 0; i < rows.length; i += _batch) {
      final end = i + _batch > rows.length ? rows.length : i + _batch;
      await _c
          .from(table)
          .upsert(rows.sublist(i, end), onConflict: 'coach_id,id');
    }
  }

  /// Löschmarke setzen statt Zeile entfernen: so erfahren andere Geräte
  /// davon. Die übrigen Spalten bleiben stehen – wichtig für Einheiten,
  /// deren Sichtbarkeit für den Athleten an athlete_id hängt.
  Future<void> _markDeleted(String table, Set<String> ids) async {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += _batch) {
      final end = i + _batch > list.length ? list.length : i + _batch;
      await _c
          .from(table)
          .update({'deleted': true})
          .eq('coach_id', store.sync.workspace!)
          .inFilter('id', list.sublist(i, end));
    }
  }

  Future<void> _push() async {
    final s = store.sync;
    final ws = s.workspace!;

    if (s.role == 'coach') {
      for (final table in const ['athletes', 'exercises', 'clips']) {
        final ids = s.takeDirty(table);
        final gone = s.takeDeleted(table);
        final rows = <Map<String, dynamic>>[
          for (final id in ids)
            if (store.remoteData(table, id) case final data?)
              {'coach_id': ws, 'id': id, 'data': data, 'deleted': false},
        ];
        try {
          await _upsert(table, rows);
          await _markDeleted(table, gone);
        } catch (_) {
          s.restoreDirty(table, ids);
          s.restoreDeleted(table, gone);
          rethrow;
        }
      }

      final planIds = s.takeDirty('sessionPlans');
      final gone = s.takeDeleted('sessions');
      final rows = <Map<String, dynamic>>[
        for (final id in planIds)
          if (store.sessionById(id) case final session?)
            {
              'coach_id': ws,
              'id': id,
              'athlete_id': session.athleteId,
              'data': sessionPlan(session),
              'deleted': false,
            },
      ];
      try {
        await _upsert('sessions', rows);
        await _markDeleted('sessions', gone);
      } catch (_) {
        s.restoreDirty('sessionPlans', planIds);
        s.restoreDeleted('sessions', gone);
        rethrow;
      }
    } else if (s.role == 'athlete') {
      // Ein Athlet lädt ausschließlich sein Protokoll hoch.
      for (final kind in const [
        'athletes',
        'exercises',
        'clips',
        'sessionPlans',
      ]) {
        s.dirty[kind]!.clear();
      }
      for (final set in s.deleted.values) {
        set.clear();
      }
    }

    final logIds = s.takeDirty('sessionLogs');
    final pending = [...logIds];
    try {
      for (final id in logIds) {
        final session = store.sessionById(id);
        if (session != null) {
          await _c
              .from('sessions')
              .update({'log': sessionLog(session)})
              .eq('coach_id', ws)
              .eq('id', id);
        }
        pending.remove(id);
      }
    } catch (_) {
      s.restoreDirty('sessionLogs', pending);
      rethrow;
    }
  }

  Future<void> _pull({bool remoteWins = false}) async {
    final s = store.sync;
    final ws = s.workspace!;
    final tables = s.role == 'coach'
        ? const ['athletes', 'exercises', 'clips', 'sessions']
        : const ['athletes', 'exercises', 'sessions'];
    const page = 500;
    for (final table in tables) {
      // Der Athlet lädt seine (wenigen) Einheiten immer vollständig: Wird
      // ihm eine Einheit entzogen, taucht sie in keiner Änderungsliste auf.
      final full = s.role == 'athlete' && table == 'sessions';
      final seen = <String>{};
      final cursor = full ? null : s.cursors[table];
      String? newest = cursor;
      for (var from = 0; ; from += page) {
        var query = _c.from(table).select().eq('coach_id', ws);
        if (cursor != null) query = query.gte('updated_at', cursor);
        final rows = await query
            .order('updated_at', ascending: true)
            .order('id', ascending: true)
            .range(from, from + page - 1);
        final list = [
          for (final r in rows) Map<String, dynamic>.from(r as Map),
        ];
        store.applyRemote(table, list, remoteWins: remoteWins);
        seen.addAll(list.map((r) => r['id'] as String));
        if (list.isNotEmpty) newest = list.last['updated_at'] as String;
        if (list.length < page) break;
      }
      if (full) store.retainSessions(seen);
      if (newest != null) s.cursors[table] = newest;
    }
  }

  Future<void> _syncMedia() async {
    final s = store.sync;
    if (s.role != 'coach') {
      s.mediaUploads.clear();
      s.mediaDeletes.clear();
      return;
    }
    final ws = s.workspace!;
    final bucket = _c.storage.from('media');
    for (final id in [...s.mediaUploads]) {
      final bytes = await store.media.loadLocal(id);
      if (bytes != null) {
        await bucket.uploadBinary(
          '$ws/$id',
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
      }
      s.mediaUploads.remove(id);
    }
    if (s.mediaDeletes.isNotEmpty) {
      final ids = [...s.mediaDeletes];
      await bucket.remove([for (final id in ids) '$ws/$id']);
      s.mediaDeletes.removeAll(ids);
    }
  }

  Future<Uint8List?> _fetchImage(String id) async {
    final ws = store.sync.workspace;
    if (ws == null || !signedIn) return null;
    return _c.storage.from('media').download('$ws/$id');
  }
}

/// Meldung für den Nutzer aus einem technischen Fehler.
String friendlyError(Object e) {
  if (e is BackendException) return e.message;
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'E-Mail oder Passwort ist falsch.';
    if (m.contains('already registered') || m.contains('already been')) {
      return 'Zu dieser E-Mail gibt es schon ein Konto.';
    }
    if (m.contains('password')) {
      return 'Das Passwort ist zu kurz oder zu schwach.';
    }
    if (m.contains('email') && m.contains('invalid')) {
      return 'Die E-Mail-Adresse ist ungültig.';
    }
    if (m.contains('not confirmed')) {
      return 'Die E-Mail-Adresse ist noch nicht bestätigt.';
    }
    if (e is AuthRetryableFetchException) {
      return 'Der Server ist nicht erreichbar.';
    }
    return 'Anmeldung fehlgeschlagen: ${e.message}';
  }
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('invalid_code')) {
      return 'Der Code ist ungültig oder abgelaufen.';
    }
    if (m.contains('already_linked')) {
      return 'Dieses Konto ist bereits mit einem Trainer verknüpft.';
    }
    if (m.contains('athlete_not_found')) {
      return 'Der Athlet wurde am Server nicht gefunden.';
    }
    if (e.code == '42501') return 'Keine Berechtigung für diese Aktion.';
    return 'Serverfehler: $m';
  }
  if (e is StorageException) {
    return 'Bild-Abgleich fehlgeschlagen: ${e.message}';
  }
  final text = e.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection') ||
      text.contains('XMLHttpRequest') ||
      text.contains('TimeoutException')) {
    return 'Der Server ist nicht erreichbar.';
  }
  return 'Unerwarteter Fehler: $text';
}

/// Stellt das [Backend] im Widget-Baum bereit.
class BackendScope extends InheritedNotifier<Backend> {
  const BackendScope({
    super.key,
    required Backend backend,
    required super.child,
  }) : super(notifier: backend);

  static Backend of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackendScope>()!.notifier!;

  static Backend read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BackendScope>()!.notifier!;
}
