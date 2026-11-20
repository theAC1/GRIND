import 'package:material_ui/material_ui.dart';

import 'main.dart';
import 'media.dart';
import 'models.dart';
import 'store.dart';
import 'sync/remote_codec.dart';
import 'theme.dart';

/// Demo-Modus zum Durchklicken ohne Server:
///   flutter run -d chrome --dart-define=DEMO=true
///
/// Beispieldaten liegen nur im Speicher. Eine Leiste über der App wechselt
/// zwischen der Trainer-Sicht und der App eines Athleten. Beim Wechsel wird
/// der Abgleich nachgestellt: Der Athlet bekommt seine Einheiten samt
/// Übungen, der Trainer das Protokoll zurück.
const demoMode = bool.fromEnvironment('DEMO');

AppStore _memoryStore() =>
    AppStore(mediaStorage: MemoryMediaStorage(), persist: false);

/// Trainer-Bestand mit Beispieldaten. [now] legt „heute“ fest.
AppStore buildDemoStore({DateTime? now}) {
  final store = _memoryStore()..seedLibraryIfEmpty();
  final today = dateOnly(now ?? DateTime.now());
  DateTime day(int offset, int hour) =>
      today.add(Duration(days: offset, hours: hour));

  Exercise ex(String name) => store.exercises.firstWhere((e) => e.name == name);
  var n = 0;
  SessionEntry entry(
    String name, {
    int sets = 3,
    String reps = '10',
    double? kg,
    String load = '',
    int? rest,
    String note = '',
    List<SetLog> logs = const [],
  }) {
    final e = ex(name);
    return SessionEntry(
      id: 'demo-e${n++}',
      exerciseId: e.id,
      name: e.name,
      category: e.category,
      sets: sets,
      reps: reps,
      weightKg: kg,
      load: load,
      restSec: rest,
      note: note,
      logs: logs,
    );
  }

  List<SetLog> done(int sets, int reps, [double? kg]) => [
    for (var i = 0; i < sets; i++) SetLog(reps: reps, weightKg: kg, done: true),
  ];

  store
    ..upsertAthlete(
      Athlete(
        id: 'demo-jonas',
        name: 'Jonas Meier',
        sport: 'Handball',
        notes: 'Schulter rechts im Blick behalten.',
      ),
    )
    ..upsertAthlete(
      Athlete(
        id: 'demo-lena',
        name: 'Lena Brunner',
        sport: 'Leichtathletik (Sprint)',
        notes: 'Achillessehne links, Aufbau seit 6 Wochen.',
      ),
    )
    ..upsertAthlete(
      Athlete(id: 'demo-mira', name: 'Mira Keller', sport: 'Fussball'),
    );

  // Beispiel für den Reel-Import: ein Clip, daraus zwei Übungen „zu prüfen“.
  const reel = 'https://www.instagram.com/reel/BEISPIEL/';
  store
    ..upsertClip(
      VideoClip(
        id: 'demo-clip',
        url: reel,
        title: 'Beispiel: Hüfte stabil in 2 Übungen',
        notes:
            'Beispiel-Clip der Demo, kein echtes Reel.\n\n'
            'Transkript: „Zwei Übungen, die ich vor jedem Beintraining '
            'mache. Erstens der Cossack Squat, tief zur Seite absitzen, '
            'Ferse bleibt unten. Zweitens der Side Plank mit Hüftabduktion, '
            'oberes Bein anheben, Becken bleibt oben.“',
        createdAt: day(-1, 20),
      ),
    )
    ..upsertExercise(
      Exercise(
        id: 'demo-clip-x00',
        name: 'Cossack Squat',
        category: ExerciseCategory.mobility,
        bodyRegion: 'Hüfte / Adduktoren',
        goals: const ['Beweglichkeit'],
        equipment: const ['Körpergewicht'],
        description: 'Tief zur Seite absitzen, die Ferse bleibt am Boden.',
        whenToUse: 'Vor dem Beintraining.',
        videoLinks: const [reel],
        sourceClipId: 'demo-clip',
        needsReview: true,
      ),
    )
    ..upsertExercise(
      Exercise(
        id: 'demo-clip-x01',
        name: 'Side Plank mit Hüftabduktion',
        category: ExerciseCategory.physio,
        bodyRegion: 'Hüfte / Rumpf',
        goals: const ['Stabilität'],
        equipment: const ['Körpergewicht'],
        description: 'Seitstütz, oberes Bein anheben, Becken bleibt oben.',
        videoLinks: const [reel],
        sourceClipId: 'demo-clip',
        needsReview: true,
      ),
    );

  store
    ..upsertSession(
      TrainingSession(
        id: 'demo-s1',
        athleteId: 'demo-jonas',
        title: 'Oberkörper Kraft',
        date: day(0, 17),
        notes: 'Aufwärmen: 5 min Rudergerät, dann Band Pull-Apart.',
        entries: [
          entry('Band Pull-Apart', sets: 2, reps: '15', load: 'rotes Band'),
          entry(
            'Bankdrücken',
            sets: 4,
            reps: '6',
            kg: 100,
            rest: 180,
            note: 'Letzter Satz darf schwer sein, aber sauber.',
          ),
          entry('Klimmzug', sets: 4, reps: '6', rest: 120),
          entry('Schulterdrücken', sets: 3, reps: '10', kg: 22.5, rest: 90),
          entry(
            'Außenrotation Schulter (Theraband)',
            sets: 3,
            reps: '12',
            load: 'gelbes Band',
          ),
        ],
      ),
    )
    ..upsertSession(
      TrainingSession(
        id: 'demo-s2',
        athleteId: 'demo-jonas',
        title: 'Unterkörper Kraft',
        date: day(-2, 17),
        done: true,
        rpe: 8,
        feedback: 'Kniebeuge lief gut, beim letzten Satz 2,5 kg mehr.',
        entries: [
          entry(
            'Kniebeuge',
            sets: 4,
            reps: '5',
            kg: 120,
            rest: 180,
            logs: [
              ...done(3, 5, 120),
              const SetLog(reps: 5, weightKg: 122.5, done: true),
            ],
          ),
          entry(
            'Rumänisches Kreuzheben',
            sets: 3,
            reps: '8',
            kg: 90,
            logs: done(3, 8, 90),
          ),
          entry(
            'Unterarmstütz (Plank)',
            sets: 3,
            reps: '45 s',
            logs: done(3, 45),
          ),
        ],
      ),
    )
    ..upsertSession(
      TrainingSession(
        id: 'demo-s3',
        athleteId: 'demo-jonas',
        title: 'Mobility & Schulter',
        date: day(2, 18),
        entries: [
          entry('BWS-Rotation', sets: 2, reps: '8'),
          entry("World's Greatest Stretch", sets: 2, reps: '5'),
          entry('Band Pull-Apart', sets: 3, reps: '15', load: 'rotes Band'),
        ],
      ),
    )
    ..upsertSession(
      TrainingSession(
        id: 'demo-s4',
        athleteId: 'demo-lena',
        title: 'Reha Achillessehne',
        date: day(0, 9),
        notes: 'Schmerz höchstens 3 von 10, sonst abbrechen und melden.',
        entries: [
          entry(
            'Sprunggelenk-Mobilisation',
            sets: 2,
            reps: '10',
            logs: done(2, 10),
          ),
          entry(
            'Exzentrisches Wadenheben',
            sets: 3,
            reps: '12',
            kg: 10,
            note: '3–4 s absenken.',
            logs: [const SetLog(reps: 12, weightKg: 10, done: true)],
          ),
          entry('Einbeinstand', sets: 3, reps: '30 s'),
          entry('Glute Bridge', sets: 3, reps: '12'),
        ],
      ),
    )
    ..upsertSession(
      TrainingSession(
        id: 'demo-s5',
        athleteId: 'demo-mira',
        title: 'Prävention Beine',
        date: day(1, 16),
        entries: [
          entry('Nordic Hamstring Curl', sets: 3, reps: '5'),
          entry('Copenhagen Plank', sets: 3, reps: '20 s'),
          entry('Ausfallschritte', sets: 3, reps: '8', kg: 12.5),
        ],
      ),
    );
  return store;
}

/// App des Athleten [athleteId], wie sie nach einem Abgleich aussähe.
AppStore demoAthleteStore(AppStore coach, String athleteId) {
  final store = _memoryStore()
    ..bindWorkspace(workspace: 'demo', role: 'athlete', athleteId: athleteId)
    ..applyRemote('athletes', [
      {'id': athleteId, 'data': coach.remoteData('athletes', athleteId)},
    ], remoteWins: true)
    ..applyRemote('exercises', [
      for (final e in coach.exercises)
        {'id': e.id, 'data': coach.remoteData('exercises', e.id)},
    ], remoteWins: true)
    ..applyRemote('sessions', [
      for (final s in coach.sessionsFor(athleteId))
        {
          'id': s.id,
          'athlete_id': athleteId,
          'data': sessionPlan(s),
          'log': sessionLog(s),
        },
    ], remoteWins: true);
  return store;
}

/// Überträgt das Protokoll des Athleten zurück in den Trainer-Bestand.
void demoReturnLogs(AppStore coach, AppStore athlete) {
  coach.applyRemote('sessions', [
    for (final s in athlete.sessions)
      if (coach.sessionById(s.id) case final plan?)
        {
          'id': s.id,
          'athlete_id': plan.athleteId,
          'data': sessionPlan(plan),
          'log': sessionLog(s),
        },
  ], remoteWins: true);
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, this.now});

  final DateTime? now;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final AppStore _coach = buildDemoStore(now: widget.now);
  AppStore? _athlete;
  String? _athleteId;

  void _select(String? athleteId) {
    if (athleteId == _athleteId) return;
    final previous = _athlete;
    if (previous != null) demoReturnLogs(_coach, previous);
    setState(() {
      _athleteId = athleteId;
      _athlete = athleteId == null ? null : demoAthleteStore(_coach, athleteId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CoachApp(
      // Neuer Schlüssel = frische Navigation beim Rollenwechsel.
      key: ValueKey(_athleteId),
      store: _athlete ?? _coach,
      banner: ListenableBuilder(
        listenable: _coach,
        builder: (context, _) => _DemoBar(
          athletes: _coach.athletes,
          selected: _athleteId,
          onSelect: _select,
        ),
      ),
    );
  }
}

class _DemoBar extends StatelessWidget {
  const _DemoBar({
    required this.athletes,
    required this.selected,
    required this.onSelect,
  });

  final List<Athlete> athletes;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? id) {
      final active = id == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: active ? AppPalette.tartanBright : const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: Key('demo_${id ?? 'coach'}'),
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelect(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? AppPalette.graphite : Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: const Color(0xFF0C0F11),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Text(
                    'DEMO',
                    style: TextStyle(
                      fontFamily: headingFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Color(0x99FFFFFF),
                    ),
                  ),
                ),
              ),
              chip('Trainer', null),
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(left: 4, right: 8),
                  child: Text(
                    'Athlet:',
                    style: TextStyle(fontSize: 13, color: Color(0x99FFFFFF)),
                  ),
                ),
              ),
              for (final a in athletes) chip(a.name.split(' ').first, a.id),
            ],
          ),
        ),
      ),
    );
  }
}
