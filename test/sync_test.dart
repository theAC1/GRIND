import 'package:coach_plan/main.dart';
import 'package:coach_plan/media.dart';
import 'package:coach_plan/models.dart';
import 'package:coach_plan/store.dart';
import 'package:coach_plan/sync/remote_codec.dart';
import 'package:coach_plan/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrainingSession session({String id = 's', String athleteId = 'a'}) =>
    TrainingSession(
      id: id,
      athleteId: athleteId,
      title: 'Kraft',
      date: DateTime(2026, 11, 20),
      entries: [
        SessionEntry(
          id: 'e1',
          exerciseId: 'seed_3',
          name: 'Bankdrücken',
          category: ExerciseCategory.kraft,
          sets: 3,
          reps: '8',
          weightKg: 100,
        ),
      ],
    );

Map<String, dynamic> sessionRow(TrainingSession s, {bool deleted = false}) => {
  'id': s.id,
  'athlete_id': s.athleteId,
  'data': sessionPlan(s),
  'log': sessionLog(s),
  'deleted': deleted,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppStore> newStore() async {
    final store = AppStore(mediaStorage: MemoryMediaStorage());
    await store.load();
    return store;
  }

  /// Tut so, als wäre alles hochgeladen.
  void flush(AppStore store) {
    for (final set in [
      ...store.sync.dirty.values,
      ...store.sync.deleted.values,
    ]) {
      set.clear();
    }
  }

  group('Änderungen verfolgen', () {
    test('Startbibliothek und alte Daten gelten als hochzuladen', () async {
      final store = await newStore();
      expect(store.sync.dirty['exercises'], hasLength(30));

      // Datenstand aus der Version ohne Abgleich (kein "sync"-Block).
      SharedPreferences.setMockInitialValues({
        AppStore.defaultStorageKey:
            '{"athletes":[{"id":"a","name":"Mia"}],"exercises":[{"id":"x",'
            '"name":"X","category":"kraft","imageIds":["img"]}],'
            '"sessions":[{"id":"s","athleteId":"a","title":"T",'
            '"date":"2026-01-01T00:00:00.000"}]}',
      });
      final old = await newStore();
      expect(old.sync.dirty['athletes'], {'a'});
      expect(old.sync.dirty['exercises'], {'x'});
      expect(old.sync.dirty['sessionPlans'], {'s'});
      expect(old.sync.mediaUploads, {'img'});
    });

    test('Plan und Protokoll einer Einheit getrennt', () async {
      final store = await newStore();
      store.upsertSession(session());
      expect(store.sync.dirty['sessionPlans'], {'s'});
      expect(store.sync.dirty['sessionLogs'], {'s'});
      flush(store);

      // Athlet hakt ab: nur das Protokoll ist geändert.
      store.updateEntry('s', toggleSet(store.sessionById('s')!.entries[0], 0));
      expect(store.sync.dirty['sessionPlans'], isEmpty);
      expect(store.sync.dirty['sessionLogs'], {'s'});
      flush(store);

      // Trainer plant um: nur der Plan.
      store.upsertSession(store.sessionById('s')!.copyWith(title: 'Neu'));
      expect(store.sync.dirty['sessionPlans'], {'s'});
      expect(store.sync.dirty['sessionLogs'], isEmpty);
      flush(store);

      // Unverändert speichern: nichts hochzuladen.
      store.upsertSession(store.sessionById('s')!);
      expect(store.sync.pendingCount, 0);
    });

    test('Löschen hinterlässt Löschmarken, auch für Einheiten', () async {
      final store = await newStore();
      store.upsertAthlete(Athlete(id: 'a', name: 'Mia'));
      store.upsertSession(session());
      flush(store);
      store.deleteAthlete('a');
      expect(store.sync.deleted['athletes'], {'a'});
      expect(store.sync.deleted['sessions'], {'s'});
      expect(store.sync.dirty['sessionPlans'], isEmpty);
    });

    test('Abgleich-Stand übersteht einen Neustart', () async {
      final store = await newStore();
      flush(store);
      store.upsertAthlete(Athlete(id: 'a', name: 'Mia'));
      store.deleteExercise('seed_0');
      store.sync.cursors['athletes'] = '2026-11-18T10:00:00+00:00';
      store.bindWorkspace(workspace: 'coach-1', role: 'coach');
      await Future<void>.delayed(Duration.zero);

      final again = await newStore();
      expect(again.sync.workspace, 'coach-1');
      expect(again.sync.role, 'coach');
      expect(again.sync.dirty['athletes'], {'a'});
      expect(again.sync.deleted['exercises'], {'seed_0'});
      expect(again.sync.dirty['exercises'], isEmpty);
    });
  });

  group('Serverstand übernehmen', () {
    test('lokal ungesicherte Änderungen haben Vorrang', () async {
      final store = await newStore();
      flush(store);
      store.upsertAthlete(Athlete(id: 'a', name: 'Lokal geändert'));
      store.applyRemote('athletes', [
        {
          'id': 'a',
          'data': {'name': 'Server'},
          'deleted': false,
        },
        {
          'id': 'b',
          'data': {'name': 'Neu vom Server'},
          'deleted': false,
        },
      ]);
      expect(store.athleteById('a')!.name, 'Lokal geändert');
      expect(store.athleteById('b')!.name, 'Neu vom Server');
      // Vom Server Übernommenes ist nicht wieder hochzuladen.
      expect(store.sync.dirty['athletes'], {'a'});
    });

    test('erster Abgleich: der Server gewinnt', () async {
      final store = await newStore(); // Startbibliothek, alles "geändert"
      store.applyRemote('exercises', [
        {
          'id': 'seed_0',
          'data': {'name': 'Kniebeuge (bearbeitet)', 'category': 'kraft'},
          'deleted': false,
        },
        {'id': 'seed_1', 'data': <String, dynamic>{}, 'deleted': true},
      ], remoteWins: true);
      expect(store.exerciseById('seed_0')!.name, 'Kniebeuge (bearbeitet)');
      expect(store.exerciseById('seed_1'), isNull);
      expect(store.sync.dirty['exercises'], hasLength(28));
      expect(store.sync.dirty['exercises'], isNot(contains('seed_0')));
    });

    test('Einheit: Plan vom Server, eigenes Protokoll bleibt', () async {
      final store = await newStore();
      store.upsertSession(session());
      flush(store);
      store.updateEntry('s', toggleSet(store.sessionById('s')!.entries[0], 0));

      final remote = session().copyWith(title: 'Vom Trainer geändert');
      store.applyRemote('sessions', [sessionRow(remote)]);

      final s = store.sessionById('s')!;
      expect(s.title, 'Vom Trainer geändert');
      expect(s.doneSets, 1, reason: 'lokal abgehakter Satz bleibt');
      expect(store.sync.dirty['sessionLogs'], {'s'});
    });

    test('Einheit: Protokoll vom Server, eigener Plan bleibt', () async {
      final store = await newStore();
      store.upsertSession(session());
      flush(store);
      store.upsertSession(store.sessionById('s')!.copyWith(title: 'Umgeplant'));

      final logged = session();
      final remote = logged.copyWith(
        entries: [completeAll(logged.entries[0])],
        rpe: () => 7,
      );
      store.applyRemote('sessions', [sessionRow(remote)]);

      final s = store.sessionById('s')!;
      expect(s.title, 'Umgeplant');
      expect((s.doneSets, s.rpe), (3, 7));
    });

    test('am Server gelöschte Einheit verschwindet', () async {
      final store = await newStore();
      store.upsertSession(session());
      flush(store);
      store.applyRemote('sessions', [sessionRow(session(), deleted: true)]);
      expect(store.sessions, isEmpty);
    });

    test('Plan/Protokoll-Zerlegung ist verlustfrei', () {
      var s = session();
      s = s.copyWith(
        entries: [
          changeSet(toggleSet(s.entries[0], 0), 1, weightKg: () => 97.5),
        ],
        done: true,
        rpe: () => 8,
        feedback: 'ok',
        notes: 'Hinweis',
      );
      final back = sessionFromRemote(
        id: s.id,
        athleteId: s.athleteId,
        plan: sessionPlan(s),
        log: sessionLog(s),
      );
      expect(back.toJson(), s.toJson());
      expect(sessionPlan(s).toString(), isNot(contains('done')));
    });
  });

  group('Konto wechseln', () {
    test('Trainer ohne Konto behält seine Daten beim Anmelden', () async {
      final store = await newStore();
      store.upsertAthlete(Athlete(id: 'a', name: 'Mia'));
      store.bindWorkspace(workspace: 'coach-1', role: 'coach');
      expect(store.athletes, hasLength(1));
      expect(store.sync.dirty['athletes'], {'a'});

      // Abmelden und wieder anmelden: nichts geht verloren.
      store.handleSignOut();
      expect(store.sync.role, isNull);
      store.upsertAthlete(Athlete(id: 'b', name: 'Tom'));
      store.bindWorkspace(workspace: 'coach-1', role: 'coach');
      expect(store.athletes, hasLength(2));
    });

    test('anderes Konto: lokaler Stand wird verworfen', () async {
      final store = await newStore();
      store.bindWorkspace(workspace: 'coach-1', role: 'coach');
      store.upsertAthlete(Athlete(id: 'a', name: 'Mia'));
      store.bindWorkspace(workspace: 'coach-2', role: 'coach');
      expect(store.athletes, isEmpty);
      expect(store.exercises, isEmpty);
      expect(store.sync.pendingCount, 0);
    });

    test(
      'Athlet: fremde Daten weg, nach Abmelden wieder lokaler Start',
      () async {
        final store = await newStore();
        store.upsertAthlete(Athlete(id: 'lokal', name: 'Eigener Eintrag'));
        store.bindWorkspace(
          workspace: 'coach-1',
          role: 'athlete',
          athleteId: 'a',
        );
        expect(store.isAthlete, isTrue);
        expect(store.athletes, isEmpty);
        expect(store.exercises, isEmpty);

        store.applyRemote('sessions', [sessionRow(session())]);
        store.retainSessions({});
        expect(store.sessions, isEmpty);

        store.handleSignOut();
        expect(store.isAthlete, isFalse);
        expect(store.sync.workspace, isNull);
        expect(store.exercises, hasLength(30));
      },
    );
  });

  testWidgets('Athleten-Ansicht: nur eigene Einheiten, kein Bearbeiten', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = await newStore();
    store.bindWorkspace(workspace: 'coach-1', role: 'athlete', athleteId: 'a');
    store.applyRemote('athletes', [
      {
        'id': 'a',
        'data': {'name': 'Mia'},
        'deleted': false,
      },
    ]);
    store.applyRemote('sessions', [
      sessionRow(session().copyWith(date: DateTime.now())),
    ]);

    await tester.pumpWidget(CoachApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Mein Training'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Einheit planen'), findsNothing);
    expect(find.text('Kraft · 1 Übung'), findsNothing);
    expect(find.text('1 Übung'), findsOneWidget);

    await tester.tap(find.text('Kraft'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bearbeiten'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Als Text kopieren'), findsOneWidget);
    expect(find.text('Löschen'), findsNothing);
    expect(find.text('Duplizieren / zuweisen'), findsNothing);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    // Abhaken geht – und landet als Protokoll-Änderung in der Warteschlange.
    await tester.tap(find.text('Training starten'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check0')));
    await tester.pumpAndSettle();
    expect(store.sessionById('s')!.doneSets, 1);
    expect(store.sync.dirty['sessionLogs'], {'s'});
    expect(store.sync.dirty['sessionPlans'], isEmpty);
  });

  testWidgets('Trainer ohne Server: Konto-Bildschirm fragt nach dem Server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = await newStore();
    await tester.pumpWidget(CoachApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account_button')));
    await tester.pumpAndSettle();
    expect(find.text('Server verbinden'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('server_url')), 'kein-server');
    await tester.tap(find.byKey(const Key('server_connect')));
    await tester.pumpAndSettle();
    expect(
      find.text('Bitte eine vollständige Adresse eingeben.'),
      findsOneWidget,
    );
  });
}
