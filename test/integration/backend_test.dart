// Ende-zu-Ende-Test gegen ein laufendes Supabase mit eingespielter
// Migration. Läuft nur, wenn die Umgebungsvariablen gesetzt sind:
//
//   COACHPLAN_TEST_URL=http://localhost:54321 \
//   COACHPLAN_TEST_ANON_KEY=... \
//   flutter test test/integration
//
// Jedes "Gerät" ist ein eigener AppStore mit eigenem Backend.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:coach_plan/media.dart';
import 'package:coach_plan/models.dart';
import 'package:coach_plan/store.dart';
import 'package:coach_plan/sync/backend.dart';
import 'package:coach_plan/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

final _url = Platform.environment['COACHPLAN_TEST_URL'];
final _key = Platform.environment['COACHPLAN_TEST_ANON_KEY'];
final _run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
var _deviceNo = 0;

class Device {
  Device._(this.store, this.backend, this.files);

  final AppStore store;
  final Backend backend;
  final MemoryMediaStorage files;

  static Future<Device> create() async {
    final files = MemoryMediaStorage();
    final store = AppStore(
      mediaStorage: files,
      storageKey: 'device_${_run}_${_deviceNo++}',
    );
    await store.load();
    final backend = Backend(store);
    await backend.configure(_url!, _key!);
    return Device._(store, backend, files);
  }

  Future<void> sync() async {
    await backend.sync();
    expect(backend.status, SyncStatus.idle, reason: backend.lastError);
  }
}

String mail(String name) => '$name-$_run@example.com';

String logsOf(SessionEntry e) => e.logs
    .map((l) => '${l.weightKg ?? '-'}x${l.reps ?? '-'}${l.done ? '✓' : ''}')
    .join(' ');

void main() {
  final skip = (_url == null || _key == null)
      ? 'COACHPLAN_TEST_URL / COACHPLAN_TEST_ANON_KEY nicht gesetzt'
      : null;

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  final devices = <Device>[];
  Future<Device> device() async {
    final d = await Device.create();
    devices.add(d);
    return d;
  }

  tearDownAll(() {
    for (final d in devices) {
      d.backend.dispose();
    }
  });

  test('Trainer und Athlet: Plan, Einladung, Protokoll, Rechte', () async {
    // --- Trainer registriert sich; Startbibliothek wird hochgeladen -------
    final coach = await device();
    await coach.backend.signUp(
      email: mail('coach'),
      password: 'geheim-123',
      role: 'coach',
      name: 'Coach',
    );
    expect(
      coach.backend.status,
      SyncStatus.idle,
      reason: coach.backend.lastError,
    );
    expect(coach.store.sync.role, 'coach');
    expect(coach.store.exercises, hasLength(30));
    expect(coach.store.sync.pendingCount, 0);

    // --- Athlet anlegen, Einheit mit Bild-Übung planen ---------------------
    final imageId = await coach.store.media.add(
      Uint8List.fromList(List.generate(64, (i) => i)),
    );
    final bench = coach.store.exercises.firstWhere(
      (e) => e.name == 'Bankdrücken',
    );
    coach.store.upsertExercise(
      Exercise.fromJson({
        ...bench.toJson(),
        'imageIds': [imageId],
        'description': 'Schulterblätter fest.',
      }),
    );
    coach.store.upsertAthlete(Athlete(id: 'mia', name: 'Mia Berger'));
    coach.store.upsertAthlete(Athlete(id: 'tom', name: 'Tom Keller'));
    coach.store.upsertSession(
      TrainingSession(
        id: 's-mia',
        athleteId: 'mia',
        title: 'Kraft Oberkörper',
        date: DateTime(2026, 11, 20),
        entries: [
          SessionEntry(
            id: 'e1',
            exerciseId: bench.id,
            name: bench.name,
            category: bench.category,
            sets: 3,
            reps: '8',
            weightKg: 100,
          ),
        ],
      ),
    );
    coach.store.upsertSession(
      TrainingSession(
        id: 's-tom',
        athleteId: 'tom',
        title: 'Nur für Tom',
        date: DateTime(2026, 11, 20),
      ),
    );
    coach.store.upsertClip(
      VideoClip(
        id: 'clip1',
        url: 'https://www.instagram.com/reel/x/',
        title: 'Privat',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    await coach.sync();
    expect(coach.store.sync.pendingCount, 0);

    final code = await coach.backend.createInvite('mia');
    expect(code, hasLength(10));
    var access = await coach.backend.athleteAccess('mia');
    expect((access.linked, access.hasValidCode), (false, true));

    // --- Athletin registriert sich und löst den Code ein -------------------
    final mia = await device();
    await mia.backend.signUp(
      email: mail('mia'),
      password: 'geheim-123',
      role: 'athlete',
      name: 'Mia',
    );
    expect(mia.store.isAthlete, isTrue);
    expect(mia.backend.linked, isFalse);
    expect(mia.store.exercises, isEmpty, reason: 'ohne Trainer keine Daten');

    await expectLater(
      mia.backend.redeemInvite('FALSCH1234'),
      throwsA(
        isA<BackendException>().having(
          (e) => e.message,
          'message',
          contains('ungültig'),
        ),
      ),
    );
    await mia.backend.redeemInvite(code.toLowerCase());
    expect(mia.backend.linked, isTrue);
    expect(mia.store.sync.athleteId, 'mia');

    // Sie sieht ihre Einheit, die Übungen des Trainers – sonst nichts.
    expect(mia.store.sessions.map((s) => s.id), ['s-mia']);
    expect(mia.store.athletes.map((a) => a.name), ['Mia Berger']);
    expect(mia.store.exercises, hasLength(30));
    expect(mia.store.clips, isEmpty);
    final entry = mia.store.sessions.single.entries.single;
    expect((entry.sets, entry.reps, entry.weightKg), (3, '8', 100));

    // Bild der Übung wird bei Bedarf vom Server geholt.
    expect(mia.files.files, isEmpty);
    final bytes = await mia.store.media.load(imageId);
    expect(bytes, hasLength(64));
    expect(mia.files.files.keys, [imageId]);

    access = await coach.backend.athleteAccess('mia');
    expect((access.linked, access.code), (true, null));
    // Der Code ist verbraucht.
    final stranger = await device();
    await stranger.backend.signUp(
      email: mail('fremd'),
      password: 'geheim-123',
      role: 'athlete',
      name: 'Fremd',
    );
    await expectLater(
      stranger.backend.redeemInvite(code),
      throwsA(isA<BackendException>()),
    );
    expect(stranger.store.sessions, isEmpty);

    // --- Athletin hakt ab; Trainer plant gleichzeitig um -------------------
    var e = mia.store.sessions.single.entries.single;
    e = toggleSet(e, 0);
    e = changeSet(e, 1, weightKg: () => 97.5);
    e = toggleSet(e, 1);
    mia.store.updateEntry('s-mia', e);
    mia.store.upsertSession(
      mia.store
          .sessionById('s-mia')!
          .copyWith(rpe: () => 8, feedback: 'Schulter ok'),
    );

    final plan = coach.store.sessionById('s-mia')!;
    coach.store.upsertSession(
      plan.copyWith(
        title: 'Kraft Oberkörper (neu)',
        entries: [plan.entries.single.copyWith(note: '2 s ablassen')],
      ),
    );

    await mia.sync();
    await coach.sync();
    await mia.sync();

    for (final d in [coach, mia]) {
      final s = d.store.sessionById('s-mia')!;
      expect(s.title, 'Kraft Oberkörper (neu)');
      expect(s.entries.single.note, '2 s ablassen');
      expect(logsOf(s.entries.single), '100.0x8✓ 97.5x8✓ 97.5x8');
      expect((s.rpe, s.feedback, s.doneSets), (8, 'Schulter ok', 2));
    }

    // --- Rechte: Athletin kann am Server nichts außer ihrem Protokoll ------
    final raw = SupabaseClient(
      _url!,
      _key!,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    addTearDown(raw.dispose);
    await raw.auth.signInWithPassword(
      email: mail('mia'),
      password: 'geheim-123',
    );
    final ws = coach.store.sync.workspace!;

    expect(await raw.from('clips').select(), isEmpty);
    expect((await raw.from('sessions').select('id')).map((r) => r['id']), [
      's-mia',
    ]);
    expect((await raw.from('athletes').select('id')).map((r) => r['id']), [
      'mia',
    ]);

    // Plan, Zuordnung und Löschmarke ändern: wird ignoriert.
    await raw
        .from('sessions')
        .update({
          'data': {'title': 'gehackt'},
          'athlete_id': 'tom',
          'deleted': true,
        })
        .eq('coach_id', ws)
        .eq('id', 's-mia');
    final after = await raw
        .from('sessions')
        .select('data,athlete_id,deleted')
        .eq('id', 's-mia')
        .single();
    expect(after['data']['title'], 'Kraft Oberkörper (neu)');
    expect((after['athlete_id'], after['deleted']), ('mia', false));

    // Fremde Einheit ändern, Übung ändern, eigene Einheit anlegen: nichts.
    await raw
        .from('sessions')
        .update({
          'log': {'done': true},
        })
        .eq('id', 's-tom');
    await raw
        .from('exercises')
        .update({
          'data': {'name': 'x'},
        })
        .eq('id', bench.id);
    await expectLater(
      raw.from('sessions').insert({
        'coach_id': ws,
        'id': 'eigen',
        'athlete_id': 'mia',
      }),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      raw.storage
          .from('media')
          .uploadBinary('$ws/fremd', Uint8List.fromList([1, 2, 3])),
      throwsA(isA<StorageException>()),
    );
    await coach.sync();
    expect(coach.store.sessionById('s-tom')!.done, isFalse);
    expect(coach.store.exerciseById(bench.id)!.name, 'Bankdrücken');
    expect(coach.store.sessionById('eigen'), isNull);

    // Die Fremde sieht weiterhin nichts, auch nicht das Bild.
    await stranger.sync();
    expect(stranger.store.sessions, isEmpty);
    expect(stranger.store.exercises, isEmpty);
    await raw.auth.signOut(scope: SignOutScope.local);
    await raw.auth.signInWithPassword(
      email: mail('fremd'),
      password: 'geheim-123',
    );
    await expectLater(
      raw.storage.from('media').download('$ws/$imageId'),
      throwsA(isA<StorageException>()),
    );

    // --- Zweites Gerät des Trainers: Serverstand gewinnt -------------------
    final tablet = await device();
    expect(tablet.store.exercises, hasLength(30)); // frische Startbibliothek
    await tablet.backend.signIn(email: mail('coach'), password: 'geheim-123');
    expect(
      tablet.backend.status,
      SyncStatus.idle,
      reason: tablet.backend.lastError,
    );
    expect(tablet.store.sync.pendingCount, 0);
    expect(tablet.store.exercises, hasLength(30));
    expect(
      tablet.store.exerciseById(bench.id)!.description,
      'Schulterblätter fest.',
      reason: 'lokale Start-Übung darf die bearbeitete nicht überschreiben',
    );
    expect(tablet.store.athletes.map((a) => a.id), ['mia', 'tom']);
    expect(tablet.store.sessions, hasLength(2));
    expect(tablet.store.clips.single.title, 'Privat');
    expect(await tablet.store.media.load(imageId), hasLength(64));

    // --- Löschen wandert zu den anderen Geräten ----------------------------
    tablet.store.deleteSession('s-mia');
    tablet.store.deleteExercise(bench.id); // Bild wird am Server entfernt
    await tablet.sync();
    await coach.sync();
    await mia.sync();
    expect(coach.store.sessionById('s-mia'), isNull);
    expect(coach.store.exerciseById(bench.id), isNull);
    expect(coach.files.files, isEmpty);
    expect(mia.store.sessions, isEmpty);
    expect(mia.store.exercises, hasLength(29));

    // --- Trainer entzieht den Zugang ---------------------------------------
    await coach.backend.unlinkAthlete('mia');
    await mia.sync();
    expect(mia.backend.linked, isFalse);
    expect(mia.store.exercises, isEmpty);
    expect(mia.store.athletes, isEmpty);

    // --- Abmelden: Trainer behält Daten, Athlet nicht ----------------------
    await coach.backend.signOut();
    expect(coach.store.sync.role, isNull);
    expect(coach.store.athletes, hasLength(2));
    // Offline weiterarbeiten und nach erneutem Anmelden hochladen.
    coach.store.upsertAthlete(Athlete(id: 'neu', name: 'Neu'));
    await coach.backend.signIn(email: mail('coach'), password: 'geheim-123');
    expect(coach.store.athletes, hasLength(3));
    await tablet.sync();
    expect(tablet.store.athleteById('neu')!.name, 'Neu');
  }, skip: skip);
}
