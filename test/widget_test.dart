import 'package:coach_plan/main.dart';
import 'package:coach_plan/media.dart';
import 'package:coach_plan/models.dart';
import 'package:coach_plan/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppStore> pumpApp(
    WidgetTester tester, {
    void Function(AppStore store)? seed,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = AppStore(mediaStorage: MemoryMediaStorage());
    await store.load();
    seed?.call(store);
    await tester.pumpWidget(CoachApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String logsOf(SessionEntry e) => e.logs
      .map((l) => '${l.weightKg ?? '-'}x${l.reps ?? '-'}${l.done ? '✓' : ''}')
      .join(' ');

  testWidgets('ohne Athleten führt "Einheit planen" zum Athleten-Tab', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Noch keine Einheiten geplant'), findsOneWidget);

    await tester.tap(find.text('Einheit planen'));
    await tester.pumpAndSettle();

    expect(find.text('Lege zuerst einen Athleten an.'), findsOneWidget);
    expect(find.text('Noch keine Athleten'), findsOneWidget);
  });

  testWidgets('Trainer: Athlet anlegen und Einheit mit Vorgabe planen', (
    tester,
  ) async {
    final store = await pumpApp(tester);

    await tester.tap(find.text('Athleten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Athlet hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('athlete_name')), 'Mia Muster');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mia Muster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einheit planen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('session_title')),
      'Kraft Oberkörper',
    );

    // Übung über die Suche nach einem Ziel-Schlagwort finden.
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise_search')), 'bankdr');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bankdrücken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hinzufügen (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Übungen (1)'), findsOneWidget);

    // Vorgabe: 4 × 8 mit 100 kg
    await tester.tap(find.text('Bankdrücken'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry_sets')), '4');
    await tester.enterText(find.byKey(const Key('entry_reps')), '8');
    await tester.enterText(find.byKey(const Key('entry_weight')), '100');
    await tester.enterText(
      find.byKey(const Key('entry_note')),
      'Schulterblätter fest',
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('4 × 8 · 100 kg\nSchulterblätter fest'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Kraft Oberkörper'), findsOneWidget);
    final e = store.sessions.single.entries.single;
    expect((e.name, e.sets, e.reps, e.weightKg), ('Bankdrücken', 4, '8', 100));
  });

  testWidgets('Athlet: Sätze abhaken, Gewicht anpassen, abschließen', (
    tester,
  ) async {
    final store = await pumpApp(
      tester,
      seed: (store) {
        store.upsertAthlete(Athlete(id: 'a', name: 'Mia Muster'));
        store.upsertSession(
          TrainingSession(
            id: 's',
            athleteId: 'a',
            title: 'Kraft Oberkörper',
            date: DateTime.now(),
            entries: [
              SessionEntry(
                id: 'e1',
                exerciseId: 'seed_3',
                name: 'Bankdrücken',
                category: ExerciseCategory.kraft,
                sets: 3,
                reps: '8',
                weightKg: 100,
                note: 'Schulterblätter fest',
              ),
              SessionEntry(
                id: 'e2',
                exerciseId: 'seed_11',
                name: 'Unterarmstütz (Plank)',
                category: ExerciseCategory.kraft,
                sets: 2,
                reps: '30 s',
              ),
            ],
          ),
        );
      },
    );
    SessionEntry entry(int i) => store.sessionById('s')!.entries[i];

    await tester.tap(find.text('Kraft Oberkörper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training starten'));
    await tester.pumpAndSettle();

    expect(find.text('Übung 1 von 2'), findsOneWidget);
    expect(find.text('0/5 Sätze'), findsOneWidget);
    expect(find.text('Vorgabe: 3 × 8 · 100 kg'), findsOneWidget);
    expect(find.text('Schulterblätter fest'), findsOneWidget);

    // Satz 1 wie vorgegeben: ein Tipp.
    await tester.tap(find.byKey(const Key('check0')));
    await tester.pumpAndSettle();
    expect(logsOf(entry(0)), '100.0x8✓ 100.0x8 100.0x8');
    expect(find.text('1/5 Sätze'), findsOneWidget);

    // Satz 2 leichter: gilt automatisch auch für Satz 3.
    await tester.tap(find.byKey(const Key('w1_minus')));
    await tester.pumpAndSettle();
    expect(find.text('97,5'), findsNWidgets(2));

    // Satz 3: Wiederholungen direkt eintippen.
    await tester.tap(find.byKey(const Key('r2_value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('number_input')), '6');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('complete_all')));
    await tester.pumpAndSettle();
    expect(logsOf(entry(0)), '100.0x8✓ 97.5x8✓ 97.5x6✓');
    expect(find.byKey(const Key('complete_all')), findsNothing);

    // Nächste Übung: Zeit statt Wiederholungen, ohne Gewicht.
    await tester.tap(find.byKey(const Key('workout_next')));
    await tester.pumpAndSettle();
    expect(find.text('Übung 2 von 2'), findsOneWidget);
    expect(find.text('Gewicht erfassen'), findsOneWidget);
    expect(find.byKey(const Key('w0_plus')), findsNothing);
    await tester.tap(find.byKey(const Key('r1_plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check0')));
    await tester.pumpAndSettle();
    expect(logsOf(entry(1)), '-x30✓ -x35');

    // Abschließen mit einem offenen Satz.
    await tester.tap(find.byKey(const Key('workout_next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 von 5 Sätzen abgehakt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rpe_7')));
    await tester.enterText(find.byKey(const Key('feedback')), 'Schulter ok');
    await tester.tap(find.byKey(const Key('finish_confirm')));
    await tester.pumpAndSettle();

    final s = store.sessionById('s')!;
    expect((s.done, s.rpe, s.feedback), (true, 7, 'Schulter ok'));

    // Trainer-Sicht zeigt Protokoll und Rückmeldung.
    expect(find.text('4/5 Sätze'), findsOneWidget);
    expect(find.text('100 kg × 8'), findsOneWidget);
    expect(find.text('97,5 kg × 6'), findsOneWidget);
    expect(find.text('Schulter ok'), findsOneWidget);
    expect(find.text('Protokoll öffnen'), findsOneWidget);
  });

  testWidgets('Übung mit eigenem Ziel und Video-Link anlegen', (tester) async {
    final store = await pumpApp(tester);

    await tester.tap(find.text('Übungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neue Übung'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exercise_name')),
      'Pogo Jumps',
    );
    await tester.tap(find.text('Schnellkraft'));
    await tester.pumpAndSettle();

    // Eigenes Schlagwort (erster "Eigenes"-Chip gehört zu "Ziel").
    await tapVisible(tester, find.text('Eigenes').first);
    await tester.enterText(find.byKey(const Key('custom_tag')), 'Reaktivkraft');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Video-Link hinzufügen'));
    await tester.enterText(find.byKey(const Key('link_field')), 'kein link');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Bitte einen gültigen Link eingeben'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('link_field')),
      'instagram.com/reel/abc123/',
    );
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('exercise_description')),
      'Kurzer Bodenkontakt, Knie fast gestreckt.',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final e = store.exercises.firstWhere((e) => e.name == 'Pogo Jumps');
    expect(e.goals, ['Schnellkraft', 'Reaktivkraft']);
    expect(e.videoLinks, ['https://instagram.com/reel/abc123/']);
    expect(store.goalVocabulary.last, 'Reaktivkraft');

    // In der Bibliothek über das Ziel auffindbar, Detailansicht zeigt alles.
    await tester.enterText(find.byKey(const Key('exercise_search')), 'reaktiv');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pogo Jumps'));
    await tester.pumpAndSettle();
    expect(
      find.text('Kurzer Bodenkontakt, Knie fast gestreckt.'),
      findsOneWidget,
    );
    expect(find.text('Reaktivkraft'), findsOneWidget);
    expect(find.text('Instagram · instagram.com'), findsOneWidget);
  });

  testWidgets('Bibliothek nach Ziel filtern', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Übungen'));
    await tester.pumpAndSettle();
    expect(find.text('Ausfallschritte'), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beweglichkeit'));
    await tester.pumpAndSettle();

    expect(find.text('Ausfallschritte'), findsNothing);
    expect(find.text('Katze-Kuh'), findsOneWidget);
    expect(find.text('90/90 Hüftrotation'), findsOneWidget);
  });

  testWidgets('Clip speichern und zwei Übungen daraus ableiten', (
    tester,
  ) async {
    final store = await pumpApp(tester);

    await tester.tap(find.text('Clips'));
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Clips'), findsOneWidget);
    await tester.tap(find.text('Clip hinzufügen'));
    await tester.pumpAndSettle();

    // Ohne gültigen Link wird nichts gespeichert.
    await tapVisible(tester, find.text('Übung daraus anlegen'));
    expect(find.text('Bitte einen gültigen Link eingeben'), findsOneWidget);
    expect(store.clips, isEmpty);

    await tester.enterText(
      find.byKey(const Key('clip_url')),
      'https://www.instagram.com/reel/XYZ/',
    );
    await tester.enterText(
      find.byKey(const Key('clip_title')),
      'Hüft-Flow für Sprinter',
    );
    await tester.enterText(
      find.byKey(const Key('clip_notes')),
      'Erst 90/90, dann Cossack Squat.',
    );
    await tester.pumpAndSettle();

    for (final name in ['90/90 Lift-Off', 'Cossack Squat']) {
      await tapVisible(tester, find.text('Übung daraus anlegen'));
      // Notizen aus dem Clip stehen beim Anlegen bereit.
      expect(find.text('Erst 90/90, dann Cossack Squat.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('exercise_name')), name);
      await tester.tap(find.text('Mobility'));
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
    }

    expect(find.text('ÜBUNGEN AUS DIESEM CLIP (2)'), findsOneWidget);
    final clip = store.clips.single;
    final derived = store.exercisesFromClip(clip.id);
    expect(derived.map((e) => e.name), ['90/90 Lift-Off', 'Cossack Squat']);
    expect(derived.every((e) => e.videoLinks.single == clip.url), isTrue);
    expect(
      derived.every((e) => e.category == ExerciseCategory.mobility),
      isTrue,
    );

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Hüft-Flow für Sprinter'), findsOneWidget);
    expect(find.text('Instagram · 2 Übungen'), findsOneWidget);
  });
}
