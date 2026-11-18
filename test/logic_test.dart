import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_plan/format.dart';
import 'package:coach_plan/links.dart';
import 'package:coach_plan/media.dart';
import 'package:coach_plan/models.dart';
import 'package:coach_plan/store.dart';
import 'package:coach_plan/taxonomy.dart';
import 'package:coach_plan/util.dart';
import 'package:coach_plan/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SessionEntry entry(
  String name, {
  int sets = 3,
  String reps = '10',
  double? weightKg,
}) => SessionEntry(
  id: newId(),
  exerciseId: 'x',
  name: name,
  category: ExerciseCategory.kraft,
  sets: sets,
  reps: reps,
  weightKg: weightKg,
);

String logsOf(SessionEntry e) => e.logs
    .map((l) => '${l.weightKg ?? '-'}x${l.reps ?? '-'}${l.done ? '✓' : ''}')
    .join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryMediaStorage files;
  AppStore newStore() => AppStore(mediaStorage: files);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    files = MemoryMediaStorage();
  });

  group('Store', () {
    test('erster Start lädt die Übungsbibliothek mit Schlagworten', () async {
      final store = newStore();
      await store.load();
      expect(store.exercises, hasLength(30));
      expect(store.athletes, isEmpty);
      expect(
        store.exercises.map((e) => e.category).toSet(),
        ExerciseCategory.values.toSet(),
      );
      expect(store.exercises.every((e) => e.goals.isNotEmpty), isTrue);
      // Alle vorbelegten Schlagworte stammen aus dem Baukasten.
      for (final e in store.exercises) {
        expect(defaultGoals, containsAll(e.goals), reason: e.name);
        expect(defaultEquipment, containsAll(e.equipment), reason: e.name);
      }
    });

    test('Daten inkl. Protokoll und Clips überleben einen Neustart', () async {
      final store = newStore();
      await store.load();
      store.upsertAthlete(Athlete(id: 'a1', name: 'Mia', sport: 'Sprint'));
      store.upsertClip(
        VideoClip(
          id: 'c1',
          url: 'https://www.instagram.com/reel/abc/',
          title: 'Hüft-Flow',
          notes: 'Transkript',
          imageIds: const ['img1'],
          createdAt: DateTime(2026, 11, 1),
        ),
      );
      final e = toggleSet(entry('Kniebeuge', weightKg: 40), 0);
      store.upsertSession(
        TrainingSession(
          id: 's1',
          athleteId: 'a1',
          title: 'Reha Knie',
          date: DateTime(2026, 11, 20),
          entries: [e.copyWith(restSec: () => 90)],
          rpe: 6,
          feedback: 'ging gut',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final reloaded = newStore();
      await reloaded.load();
      expect(reloaded.athletes.single.name, 'Mia');
      final s = reloaded.sessionById('s1')!;
      expect(s.date, DateTime(2026, 11, 20));
      expect(s.rpe, 6);
      expect(s.feedback, 'ging gut');
      expect(s.entries.single.weightKg, 40);
      expect(s.entries.single.restSec, 90);
      expect(logsOf(s.entries.single), '40.0x10✓ 40.0x10 40.0x10');
      expect(s.doneSets, 1);
      expect(s.totalSets, 3);
      final c = reloaded.clips.single;
      expect(c.title, 'Hüft-Flow');
      expect(c.imageIds, ['img1']);
      expect(c.createdAt, DateTime(2026, 11, 1));
    });

    test('altes Datenformat wird übernommen', () {
      final e = SessionEntry.fromJson({
        'id': 'e',
        'exerciseId': 'x',
        'name': 'Kniebeuge',
        'category': 'kraft',
        'sets': 3,
        'reps': '8',
        'load': '62,5 kg',
      });
      expect(e.weightKg, 62.5);
      expect(e.load, '');
      expect(e.logs, isEmpty);

      final band = SessionEntry.fromJson({
        'id': 'e',
        'name': 'Pull-Apart',
        'load': 'rotes Band',
      });
      expect(band.weightKg, isNull);
      expect(band.load, 'rotes Band');

      final ex = Exercise.fromJson({
        'id': 'x',
        'name': 'Alt',
        'category': 'physio',
        'videoUrl': 'https://youtu.be/abcdefghijk',
      });
      expect(ex.videoLinks, ['https://youtu.be/abcdefghijk']);
      expect(ex.goals, isEmpty);
    });

    test('Athlet löschen entfernt auch dessen Einheiten', () async {
      final store = newStore();
      await store.load();
      store.upsertAthlete(Athlete(id: 'a1', name: 'Mia'));
      store.upsertAthlete(Athlete(id: 'a2', name: 'Tom'));
      for (final (id, athlete) in [('s1', 'a1'), ('s2', 'a2')]) {
        store.upsertSession(
          TrainingSession(
            id: id,
            athleteId: athlete,
            title: 'T',
            date: DateTime(2026, 1, 1),
          ),
        );
      }
      store.deleteAthlete('a1');
      expect(store.sessions.map((s) => s.id), ['s2']);
    });

    test('upcoming/past trennen am heutigen Tag', () async {
      final store = newStore();
      await store.load();
      final now = DateTime(2026, 11, 18, 15);
      for (final (id, date) in [
        ('gestern', DateTime(2026, 11, 17)),
        ('heute', DateTime(2026, 11, 18)),
        ('morgen', DateTime(2026, 11, 19)),
      ]) {
        store.upsertSession(
          TrainingSession(id: id, athleteId: 'a', title: id, date: date),
        );
      }
      expect(store.upcoming(now: now).map((s) => s.id), ['heute', 'morgen']);
      expect(store.past(now: now).map((s) => s.id), ['gestern']);
    });

    test('duplizieren erzeugt offene Kopie ohne Protokoll', () async {
      final store = newStore();
      await store.load();
      final source = TrainingSession(
        id: 's1',
        athleteId: 'a1',
        title: 'Kraft',
        date: DateTime(2026, 11, 18),
        done: true,
        rpe: 8,
        feedback: 'hart',
        entries: [
          completeAll(entry('Kniebeuge', weightKg: 80)),
          entry('Plank', reps: '30 s'),
        ],
      );
      store.upsertSession(source);
      final copy = store.duplicateSession(
        source,
        athleteId: 'a2',
        date: DateTime(2026, 11, 25, 10),
      );
      expect(copy.id, isNot(source.id));
      expect(copy.athleteId, 'a2');
      expect(copy.date, DateTime(2026, 11, 25));
      expect(copy.done, isFalse);
      expect(copy.rpe, isNull);
      expect(copy.feedback, '');
      expect(copy.entries.map((e) => e.name), ['Kniebeuge', 'Plank']);
      expect(copy.entries.first.weightKg, 80);
      expect(copy.doneSets, 0);
      expect(store.sessionById('s1')!.doneSets, 3);
    });

    test('defekte Daten werden gesichert statt verworfen', () async {
      SharedPreferences.setMockInitialValues({
        AppStore.defaultStorageKey: '{kaputt',
      });
      final store = newStore();
      await store.load();
      expect(store.exercises, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('coachplan_data_v1_corrupt_backup'), '{kaputt');
    });

    test('JSON-Roundtrip der Einheit', () {
      final s = TrainingSession(
        id: 's',
        athleteId: 'a',
        title: 'T',
        date: DateTime(2026, 3, 5),
        notes: 'n',
        done: true,
        rpe: 7,
        feedback: 'f',
        entries: [
          toggleSet(entry('A', weightKg: 97.5), 1).copyWith(note: 'langsam'),
        ],
      );
      final back = TrainingSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.toJson(), s.toJson());
    });

    test('eigene Schlagworte erweitern den Baukasten', () async {
      final store = newStore();
      await store.load();
      store.upsertExercise(
        Exercise(
          id: 'neu',
          name: 'Pogo Jumps',
          category: ExerciseCategory.kraft,
          goals: const ['Reaktivkraft', 'Schnellkraft'],
          equipment: const ['Hürden'],
        ),
      );
      expect(store.goalVocabulary.take(defaultGoals.length), defaultGoals);
      expect(store.goalVocabulary.last, 'Reaktivkraft');
      expect(store.equipmentVocabulary.last, 'Hürden');
      store.deleteExercise('neu');
      expect(store.goalVocabulary, defaultGoals);
    });

    test('Bilder werden erst gelöscht, wenn niemand sie mehr nutzt', () async {
      final store = newStore();
      await store.load();
      final shared = await store.media.add(Uint8List.fromList([1]));
      final own = await store.media.add(Uint8List.fromList([2]));
      final discarded = await store.media.add(Uint8List.fromList([3]));

      store.upsertClip(
        VideoClip(
          id: 'c',
          url: 'https://instagram.com/reel/x',
          imageIds: [shared],
          createdAt: DateTime(2026),
        ),
      );
      store.upsertExercise(
        Exercise(
          id: 'e',
          name: 'E',
          category: ExerciseCategory.physio,
          imageIds: [shared, own],
          sourceClipId: 'c',
        ),
      );
      // Im Editor hinzugefügt, aber nicht gespeichert.
      store.releaseMedia([shared, own, discarded]);
      expect(files.files.keys, unorderedEquals([shared, own]));

      // Bild aus der Übung entfernt.
      store.upsertExercise(
        Exercise(
          id: 'e',
          name: 'E',
          category: ExerciseCategory.physio,
          imageIds: [shared],
          sourceClipId: 'c',
        ),
      );
      expect(files.files.keys, [shared]);

      // Clip weg: Übung hält das Bild weiter.
      store.deleteClip('c');
      expect(files.files.keys, [shared]);
      expect(store.exercisesFromClip('c').single.id, 'e');
      expect(store.clipById('c'), isNull);

      store.deleteExercise('e');
      expect(files.files, isEmpty);
      expect(await store.media.load(shared), isNull);
    });
  });

  group('Trainingsprotokoll', () {
    test('Zielwert aus dem Freitext', () {
      RepsTarget t(String s) => parseRepsTarget(s);
      expect((t('10').value, t('10').unit), (10, 'Wdh.'));
      expect((t('8–12').value, t('8–12').unit), (8, 'Wdh.'));
      expect((t('30 s').value, t('30 s').unit, t('30 s').step), (30, 's', 5));
      expect((t('45s').value, t('45s').unit), (45, 's'));
      expect((t('2 min').value, t('2 min').unit), (2, 'min'));
      expect((t('max').value, t('max').unit), (null, 'Wdh.'));
      expect((t('').value, t('').unit), (null, 'Wdh.'));
    });

    test('Vorgabe wird als Satzliste vorbelegt', () {
      final e = entry('Bankdrücken', reps: '8', weightKg: 100);
      expect(
        logsOf(e.copyWith(logs: workingLogs(e))),
        '100.0x8 100.0x8 100.0x8',
      );
      expect(e.plannedSetCount, 3);
      expect(e.doneSetCount, 0);
    });

    test('ein Tipp hakt den Satz wie vorgegeben ab, zweiter nimmt zurück', () {
      var e = entry('Bankdrücken', reps: '8', weightKg: 100);
      e = toggleSet(e, 0);
      expect(logsOf(e), '100.0x8✓ 100.0x8 100.0x8');
      expect(e.isComplete, isFalse);
      e = toggleSet(e, 0);
      expect(e.doneSetCount, 0);
    });

    test('geändertes Gewicht gilt für die folgenden offenen Sätze', () {
      var e = entry('Bankdrücken', reps: '8', weightKg: 100);
      e = toggleSet(e, 0);
      e = changeSet(e, 1, weightKg: () => 97.5);
      expect(logsOf(e), '100.0x8✓ 97.5x8 97.5x8');
      // Nur Satz 3 schafft weniger Wiederholungen.
      e = changeSet(e, 2, reps: () => 6);
      expect(logsOf(e), '100.0x8✓ 97.5x8 97.5x6');
      // Erledigte Sätze bleiben unangetastet.
      e = changeSet(e, 0, reps: () => 9);
      expect(logsOf(e), '100.0x9✓ 97.5x8 97.5x6');
    });

    test('alle abhaken, Zusatzsatz, Zusatzsatz entfernen', () {
      var e = entry('Klimmzug', reps: '6');
      e = completeAll(e);
      expect(logsOf(e), '-x6✓ -x6✓ -x6✓');
      expect(e.isComplete, isTrue);
      expect(canRemoveLastSet(e), isFalse);

      e = addSet(e);
      expect(e.plannedSetCount, 4);
      expect(e.isComplete, isFalse);
      expect(canRemoveLastSet(e), isTrue);
      e = removeLastSet(e);
      expect(e.plannedSetCount, 3);
      // Vorgegebene Sätze lassen sich nicht wegnehmen.
      expect(removeLastSet(e).logs, hasLength(3));
    });

    test('mehr Sätze in der Vorgabe füllen offene Sätze auf', () {
      var e = toggleSet(entry('A', reps: '10', weightKg: 50), 0);
      e = e.copyWith(sets: 4, logs: e.logs.where((l) => l.done).toList());
      expect(e.plannedSetCount, 4);
      expect(workingLogs(e), hasLength(4));
      expect(workingLogs(e).last.weightKg, 50);
    });
  });

  group('Links', () {
    test('Eingaben werden zu Adressen', () {
      expect(
        parseHttpUrl('instagram.com/reel/abc').toString(),
        'https://instagram.com/reel/abc',
      );
      expect(parseHttpUrl(' https://youtu.be/x '), isNotNull);
      expect(parseHttpUrl(''), isNull);
      expect(parseHttpUrl('kein link'), isNull);
      expect(parseHttpUrl('javascript:alert(1)'), isNull);
      expect(parseHttpUrl('ftp://example.com/a'), isNull);
    });

    test('Plattform', () {
      expect(
        platformOf('https://www.instagram.com/reel/x/'),
        LinkPlatform.instagram,
      );
      expect(platformOf('https://youtu.be/abc'), LinkPlatform.youtube);
      expect(
        platformOf('https://m.youtube.com/watch?v=a'),
        LinkPlatform.youtube,
      );
      expect(platformOf('https://vm.tiktok.com/x'), LinkPlatform.tiktok);
      expect(platformOf('https://example.com/video'), LinkPlatform.other);
      // Fremde Domain, die nur so aussieht.
      expect(
        platformOf('https://notyoutube.com/watch?v=a'),
        LinkPlatform.other,
      );
    });

    test('YouTube-ID und Vorschaubild', () {
      const id = 'dQw4w9WgXcQ';
      for (final url in [
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&t=10s',
        'https://youtu.be/$id?si=abc',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/embed/$id',
        'youtube.com/shorts/$id?feature=share',
      ]) {
        expect(youtubeId(url), id, reason: url);
      }
      expect(
        youtubeThumbnail('https://youtu.be/$id'),
        'https://img.youtube.com/vi/$id/hqdefault.jpg',
      );
      expect(youtubeId('https://www.youtube.com/@kanal'), isNull);
      expect(youtubeThumbnail('https://www.instagram.com/reel/$id/'), isNull);
    });
  });

  group('Formatierung', () {
    test('Zahlen', () {
      expect(fmtNum(100), '100');
      expect(fmtNum(97.5), '97,5');
      expect(fmtNum(1.25), '1,25');
      expect(parseNum('97,5'), 97.5);
      expect(parseNum(' 60 '), 60);
      expect(parseNum('abc'), isNull);
    });

    test('Datum', () {
      expect(formatDate(DateTime(2026, 11, 18)), 'Mi, 18.11.2026');
      final now = DateTime(2026, 11, 18, 23, 30);
      expect(
        relativeDate(DateTime(2026, 11, 18), now: now),
        startsWith('Heute'),
      );
      expect(
        relativeDate(DateTime(2026, 11, 19), now: now),
        startsWith('Morgen'),
      );
      expect(
        relativeDate(DateTime(2026, 11, 17), now: now),
        startsWith('Gestern'),
      );
      expect(relativeDate(DateTime(2026, 11, 25), now: now), 'Mi, 25.11.2026');
    });

    test('Vorgabe und protokollierte Sätze', () {
      expect(entrySummary(entry('A')), '3 × 10');
      expect(
        entrySummary(
          entry(
            'A',
            weightKg: 62.5,
          ).copyWith(load: 'Safety Bar', restSec: () => 90),
        ),
        '3 × 10 · 62,5 kg · Safety Bar · Pause 90 s',
      );
      expect(entrySummary(entry('A', sets: 1, reps: '')), '1 Satz');

      var e = entry('Bank', reps: '8', weightKg: 100);
      e = toggleSet(e, 0);
      e = changeSet(e, 1, weightKg: () => 97.5, reps: () => 7);
      e = toggleSet(e, 1);
      expect(doneSetTexts(e), ['100 kg × 8', '97,5 kg × 7']);
      expect(doneSetTexts(completeAll(entry('Plank', sets: 1, reps: '30 s'))), [
        '30 s',
      ]);
    });

    test('Einheit als Text mit Video-Links', () {
      final ex = Exercise(
        id: 'x',
        name: 'Band Pull-Apart',
        category: ExerciseCategory.physio,
        videoLinks: const ['https://youtu.be/abcdefghijk'],
      );
      final text = sessionAsText(
        TrainingSession(
          id: 's',
          athleteId: 'a',
          title: 'Reha Schulter',
          date: DateTime(2026, 11, 18),
          entries: [entry('Band Pull-Apart').copyWith(note: 'langsam')],
        ),
        Athlete(id: 'a', name: 'Mia'),
        exerciseOf: (id) => id == 'x' ? ex : null,
      );
      expect(
        text,
        'Reha Schulter\n'
        'Athlet: Mia\n'
        'Datum: Mi, 18.11.2026\n'
        '\n'
        '1. Band Pull-Apart (Kraft)\n'
        '   3 × 10\n'
        '   → langsam\n'
        '   Video: https://youtu.be/abcdefghijk',
      );
    });
  });
}
