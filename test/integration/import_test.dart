// Prüft, dass ein Import von tools/reel_import in der App ankommt.
// Vorher mit demselben Trainer-Konto "reel_import.py upload" ausführen.
//
//   COACHPLAN_TEST_URL=… COACHPLAN_TEST_ANON_KEY=… \
//   COACHPLAN_TEST_IMPORT_EMAIL=… COACHPLAN_TEST_IMPORT_PASSWORD=… \
//   flutter test test/integration/import_test.dart
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:coach_plan/media.dart';
import 'package:coach_plan/models.dart';
import 'package:coach_plan/store.dart';
import 'package:coach_plan/sync/backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final env = Platform.environment;
  final url = env['COACHPLAN_TEST_URL'];
  final key = env['COACHPLAN_TEST_ANON_KEY'];
  final email = env['COACHPLAN_TEST_IMPORT_EMAIL'];
  final password = env['COACHPLAN_TEST_IMPORT_PASSWORD'];
  final skip = [url, key, email, password].contains(null)
      ? 'COACHPLAN_TEST_IMPORT_* nicht gesetzt'
      : null;

  test('importierter Clip und Übungen erscheinen nach dem Abgleich', () async {
    SharedPreferences.setMockInitialValues({});
    final files = MemoryMediaStorage();
    final store = AppStore(mediaStorage: files, storageKey: 'import_check');
    await store.load();
    final backend = Backend(store);
    addTearDown(backend.dispose);
    await backend.configure(url!, key!);
    await backend.signIn(email: email!, password: password!);
    expect(backend.status, SyncStatus.idle, reason: backend.lastError);

    final clip = store.clips.singleWhere((c) => c.id.startsWith('imp-'));
    expect(clip.url, 'https://instagram.com/reel/DEMOimport1');
    expect(clip.title, 'Hüft-Flow in 3 Übungen');
    expect(clip.notes, contains('Transkript (automatisch, de):'));
    expect(clip.notes, contains('Cossack Squat'));
    expect(clip.imageIds, hasLength(6));

    final derived = store.exercisesFromClip(clip.id);
    expect(derived.map((e) => e.name), [
      '90/90 Hüftrotation (Reel)',
      'Cossack Squat',
    ]);
    for (final e in derived) {
      expect(e.category, ExerciseCategory.mobility);
      expect(e.needsReview, isTrue);
      expect(e.videoLinks, [clip.url]);
      expect(e.imageIds, hasLength(2));
      expect(e.description, isNotEmpty);
      expect(e.whenToUse, contains('Beintraining'));
    }
    expect(derived.first.goals, ['Beweglichkeit', 'Aktivierung']);
    expect(derived.first.equipment, ['Körpergewicht']);

    // Standbild kommt als JPEG vom Server.
    final bytes = await store.media.load(derived.first.imageIds.first);
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 3), [0xFF, 0xD8, 0xFF]);

    // Die Startbibliothek bleibt daneben vollständig.
    expect(store.exercises, hasLength(32));
    expect(store.sync.pendingCount, 0);
  }, skip: skip);
}
