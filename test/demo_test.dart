import 'package:coach_plan/demo.dart';
import 'package:coach_plan/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12);

  test('Athlet sieht nur eigene Einheiten, Protokoll kommt zurück', () {
    final coach = buildDemoStore(now: now);
    final athlete = demoAthleteStore(coach, 'demo-jonas');
    expect(athlete.isAthlete, isTrue);
    expect(athlete.sessions.map((s) => s.athleteId).toSet(), {'demo-jonas'});
    expect(athlete.sessions.length, 3);
    expect(athlete.clips, isEmpty);
    expect(athlete.athletes.single.name, 'Jonas Meier');

    final s = athlete.sessionById('demo-s1')!;
    final bench = s.entries.firstWhere((e) => e.name == 'Bankdrücken');
    athlete.updateEntry(s.id, toggleSet(bench, 0));
    demoReturnLogs(coach, athlete);

    final back = coach.sessionById('demo-s1')!;
    expect(back.doneSets, 1);
    expect(back.title, 'Oberkörper Kraft');
    // Einheiten anderer Athleten bleiben unberührt.
    expect(coach.sessionById('demo-s4')!.doneSets, 3);
  });

  testWidgets('Umschalten zwischen Trainer und Athlet', (tester) async {
    // Ohne festes Datum: der Plan teilt nach der echten Uhr in heute/vergangen.
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();
    expect(find.text('Athleten'), findsWidgets);
    expect(find.text('Oberkörper Kraft'), findsOneWidget);
    expect(find.text('Reha Achillessehne'), findsOneWidget);

    await tester.tap(find.byKey(const Key('demo_demo-lena')));
    await tester.pumpAndSettle();
    expect(find.text('Mein Training'), findsOneWidget);
    expect(find.text('Reha Achillessehne'), findsOneWidget);
    expect(find.text('Oberkörper Kraft'), findsNothing);

    await tester.tap(find.byKey(const Key('demo_coach')));
    await tester.pumpAndSettle();
    expect(find.text('Mein Training'), findsNothing);
    expect(find.text('Oberkörper Kraft'), findsOneWidget);
  });
}
