import 'dart:convert';
import 'dart:io';

import 'package:coach_plan/main.dart';
import 'package:coach_plan/media.dart';
import 'package:coach_plan/models.dart';
import 'package:coach_plan/store.dart';
import 'package:coach_plan/taxonomy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Baukasten des Import-Werkzeugs stimmt mit der App überein', () {
    final json = jsonDecode(
      File('tools/reel_import/taxonomy.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(json['goals'], defaultGoals);
    expect(json['equipment'], defaultEquipment);
    expect(json['categories'], [
      for (final c in ExerciseCategory.values) c.name,
    ]);
  });

  test('Prüf-Marke: nur gesetzt gespeichert, alte Daten ohne Marke', () {
    final imported = Exercise.fromJson({
      'id': 'imp-1-x00',
      'name': 'Cossack Squat',
      'category': 'mobility',
      'needsReview': true,
    });
    expect(imported.needsReview, isTrue);
    expect(imported.toJson()['needsReview'], isTrue);

    final plain = Exercise.fromJson({
      'id': 'x',
      'name': 'X',
      'category': 'kraft',
    });
    expect(plain.needsReview, isFalse);
    expect(plain.toJson().containsKey('needsReview'), isFalse);
  });

  testWidgets('importierte Übung prüfen: Filter, Hinweis, Speichern', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = AppStore(mediaStorage: MemoryMediaStorage());
    await store.load();
    // So kommt eine importierte Übung vom Server.
    store.applyRemote('exercises', [
      {
        'id': 'imp-1-x00',
        'deleted': false,
        'data': {
          'name': 'Cossack Squat',
          'category': 'mobility',
          'goals': ['Beweglichkeit'],
          'description': 'Tief zur Seite absitzen.',
          'videoLinks': ['https://instagram.com/reel/DEMO'],
          'sourceClipId': 'imp-1',
          'needsReview': true,
        },
      },
    ]);
    await tester.pumpWidget(CoachApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Übungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review_filter')));
    await tester.pumpAndSettle();
    expect(find.text('Zu prüfen (1)'), findsOneWidget);
    expect(find.text('Ausfallschritte'), findsNothing);
    expect(find.text('Prüfen'), findsOneWidget);

    await tester.tap(find.text('Cossack Squat'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Automatisch aus einem Clip erstellt'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final saved = store.exerciseById('imp-1-x00')!;
    expect(saved.needsReview, isFalse);
    expect(saved.sourceClipId, 'imp-1');
    expect(saved.videoLinks, ['https://instagram.com/reel/DEMO']);
    expect(
      find.textContaining('Automatisch aus einem Clip erstellt'),
      findsNothing,
    );
    // Die Änderung wird hochgeladen.
    expect(store.sync.dirty['exercises'], contains('imp-1-x00'));

    // Nichts mehr zu prüfen: der Filter verschwindet.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_filter')), findsNothing);
    expect(find.text('Ausfallschritte'), findsOneWidget);
  });
}
