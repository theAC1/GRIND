import 'util.dart';

/// Belastungsmethoden (Wellen, Cluster) als Vorlagen: Prozent vom 1RM je
/// Satz. Aus dem 1RM des Athleten werden daraus feste Kilos.
///
/// Die Werte im [grundset] stammen aus der Recherche vom November 2026
/// (Quelle je Methode in [LoadMethod.source]); wo eine Quelle nur Teile
/// nennt, steht das dabei. Alles ist als Startpunkt gedacht und soll vom
/// Trainer geprüft und angepasst werden.
enum MethodKind { welle, cluster }

/// Ein Satz einer Methode. [reps] mit mehreren Einträgen ist ein
/// Cluster-Satz: Teil-Sätze mit [intraRestSec] Kurzpause dazwischen.
class MethodSet {
  const MethodSet(this.percent, this.reps, {this.intraRestSec, this.restSec});

  /// Prozent vom 1RM (z. B. 87.5).
  final double percent;
  final List<int> reps;
  final int? intraRestSec;

  /// Pause nach dem Satz.
  final int? restSec;

  bool get isCluster => reps.length > 1;
  int get totalReps => reps.fold(0, (a, b) => a + b);

  /// "5" oder "2+2+1".
  String get repsLabel => reps.join('+');
}

class LoadMethod {
  const LoadMethod({
    required this.id,
    required this.name,
    required this.kind,
    required this.goal,
    required this.sets,
    this.note = '',
    this.source = '',
  });

  final String id;
  final String name;
  final MethodKind kind;
  final String goal;
  final List<MethodSet> sets;
  final String note;

  /// Woher die Zahlen stammen (für den Trainer nachvollziehbar).
  final String source;

  double get topPercent =>
      sets.map((s) => s.percent).reduce((a, b) => a > b ? a : b);
}

/// Ein Satz mit ausgerechnetem Gewicht.
class ResolvedSet {
  const ResolvedSet(this.spec, this.weightKg);

  final MethodSet spec;
  final double weightKg;

  @override
  String toString() => '${spec.repsLabel} × ${fmtNum(weightKg)} kg';
}

/// Rundet auf die kleinste ladbare Stufe (Standard 2,5 kg).
double roundLoad(double kg, {double step = 2.5}) {
  if (step <= 0) return kg;
  return (kg / step).round() * step;
}

/// Rechnet eine Methode für ein 1RM in Kilos um.
List<ResolvedSet> resolveMethod(
  LoadMethod method,
  double oneRmKg, {
  double step = 2.5,
}) => [
  for (final s in method.sets)
    ResolvedSet(s, roundLoad(oneRmKg * s.percent / 100, step: step)),
];

/// Schätzt das 1RM aus einem Satz (Epley: Gewicht × (1 + Wdh/30)).
/// Nur als Vorschlag gedacht; ab etwa 10 Wiederholungen wird die Schätzung
/// ungenau. Eine einzelne Wiederholung gilt als das 1RM selbst.
double? estimateOneRm(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return null;
  if (reps == 1) return weightKg;
  return weightKg * (1 + reps / 30);
}

List<MethodSet> _waves(List<List<double>> percents, List<int> reps, int rest) =>
    [
      for (final wave in percents)
        for (var i = 0; i < reps.length; i++)
          MethodSet(wave[i], [reps[i]], restSec: rest),
    ];

List<MethodSet> _repeat(int n, MethodSet set) => List.filled(n, set);

/// Grundbestand an Methoden.
final List<LoadMethod> grundset = [
  LoadMethod(
    id: 'welle-531',
    name: 'Welle 5/3/1',
    kind: MethodKind.welle,
    goal: 'Maximalkraft',
    sets: _waves(
      [
        [80, 90, 95],
        [80, 90, 95],
      ],
      [5, 3, 1],
      180,
    ),
    note: '2 Wellen, eine dritte nur, wenn die zweite sauber war.',
    source: 'Vorgabe des Trainers (80/90/95 %, 2–3 Durchgänge).',
  ),
  LoadMethod(
    id: 'welle-321',
    name: 'Welle 3/2/1',
    kind: MethodKind.welle,
    goal: 'Maximalkraft',
    sets: _waves(
      [
        [85, 87.5, 90],
        [87.5, 90, 92.5],
        [90, 92.5, 95],
      ],
      [3, 2, 1],
      180,
    ),
    note: 'Jede Welle startet 2,5 % höher.',
    source:
        'Clean Health (K. Leggett): 1. Welle 85/87,5/90 %, 3. Welle '
        '90/92,5/95 %. Die 2. Welle ist dazwischen interpoliert.',
  ),
  LoadMethod(
    id: 'welle-321-schwer',
    name: 'Welle 3/2/1 schwer',
    kind: MethodKind.welle,
    goal: 'Maximalkraft (nahe Maximum)',
    sets: _waves(
      [
        [90, 95, 97.5],
        [92.5, 97.5, 100],
      ],
      [3, 2, 1],
      240,
    ),
    note:
        'Endet am 1RM. Nur für Erfahrene, mit Sicherung; 2. Welle nur, '
        'wenn die 1. ohne Mühe ging.',
    source:
        'Elite FTS: ca. 90/95/97,5 %, nächste Welle +2,5–5 %. Die Quelle '
        'nennt 60–90 s Pause; hier länger angesetzt.',
  ),
  LoadMethod(
    id: 'welle-543',
    name: 'Welle 5/4/3',
    kind: MethodKind.welle,
    goal: 'Kraft',
    sets: _waves(
      [
        [75, 80, 85],
        [75, 80, 85],
        [75, 80, 85],
      ],
      [5, 4, 3],
      150,
    ),
    note: 'Drei gleiche Wellen; steigern, wenn alle sauber waren.',
    source: 'Kniebeuge-Vorlage 75 % × 5, 80 % × 4, 85 % × 3, drei Wellen.',
  ),
  LoadMethod(
    id: 'welle-753',
    name: 'Welle 7/5/3',
    kind: MethodKind.welle,
    goal: 'Kraft und Hypertrophie',
    sets: _waves(
      [
        [70, 80, 90],
        [72.5, 82.5, 92.5],
      ],
      [7, 5, 3],
      150,
    ),
    note: 'Zweite Welle 2,5 % schwerer.',
    source: 'Elite FTS: ca. 70/80/90 %, nächste Welle +2,5–5 %.',
  ),
  LoadMethod(
    id: 'welle-642',
    name: 'Welle 6/4/2',
    kind: MethodKind.welle,
    goal: 'Kraft und Hypertrophie',
    sets: _waves(
      [
        [77.5, 85, 90],
        [80, 87.5, 92.5],
      ],
      [6, 4, 2],
      150,
    ),
    note: 'Zweite Welle 2,5 % schwerer.',
    source:
        'Schema und „zweite Welle schwerer“ aus mehreren Quellen; die '
        'Prozentwerte sind eine eigene Ableitung, keine Quelle nennt sie.',
  ),
  LoadMethod(
    id: 'kontrast-16',
    name: 'Kontrast 1/6',
    kind: MethodKind.welle,
    goal: 'Maximalkraft',
    sets: _waves(
      [
        [92.5, 80],
        [95, 82.5],
        [97.5, 85],
      ],
      [1, 6],
      210,
    ),
    note:
        'Schwere Einzelwiederholung, danach 6 Wiederholungen; jedes Paar '
        'etwas schwerer. Die Einzelne darf nicht zum Kampf werden.',
    source:
        'Nach Poliquin. Quellen nennen nur „Einzelne nahe am 2RM, jedes '
        'Paar schwerer“; die Prozentwerte sind eine eigene Ableitung.',
  ),
  LoadMethod(
    id: 'cluster-5x1',
    name: 'Cluster 5 × 1',
    kind: MethodKind.cluster,
    goal: 'Maximalkraft',
    sets: _repeat(
      4,
      const MethodSet(90, [1, 1, 1, 1, 1], intraRestSec: 20, restSec: 180),
    ),
    note: 'Fünf Einzelne mit dem 4RM-Gewicht, 20 s dazwischen.',
    source:
        'bodybuilding.com: 4RM-Gewicht, 5 Einzelne, 20 s Pause. Satzzahl '
        'und Satzpause sind dort nicht genannt (hier 4 Sätze, 3 min).',
  ),
  LoadMethod(
    id: 'cluster-221',
    name: 'Cluster 2+2+1',
    kind: MethodKind.cluster,
    goal: 'Maximalkraft',
    sets: _repeat(
      3,
      const MethodSet(90, [2, 2, 1], intraRestSec: 15, restSec: 180),
    ),
    source: '3 × 5 (2-2-1), 15 s Kurzpause, 90 %, 3 min Satzpause.',
  ),
  LoadMethod(
    id: 'cluster-211',
    name: 'Cluster 2+1+1',
    kind: MethodKind.cluster,
    goal: 'Maximalkraft (schwer)',
    sets: _repeat(
      2,
      const MethodSet(92.5, [2, 1, 1], intraRestSec: 20, restSec: 240),
    ),
    source:
        '2 × 4 (2-1-1), 20 s Kurzpause, 93 %, 4 min Satzpause '
        '(hier auf 92,5 % gerundet).',
  ),
  LoadMethod(
    id: 'cluster-521',
    name: 'Extended Fives 5+2+1',
    kind: MethodKind.cluster,
    goal: 'Kraft und Hypertrophie',
    sets: _repeat(
      3,
      const MethodSet(85, [5, 2, 1], intraRestSec: 15, restSec: 150),
    ),
    note: '6RM-Gewicht: 5 Wiederholungen, kurz ablegen, 2, kurz ablegen, 1.',
    source:
        'Nach Thibaudeau: 6RM-Last, 5 + 2 + 1 mit 10–15 s, 2–3 min '
        'Satzpause. Satzzahl nicht genannt (hier 3); 6RM als 85 % angesetzt.',
  ),
  LoadMethod(
    id: 'cluster-schnellkraft',
    name: 'Schnellkraft-Cluster 2+2+2',
    kind: MethodKind.cluster,
    goal: 'Schnellkraft',
    sets: _repeat(
      4,
      const MethodSet(60, [2, 2, 2], intraRestSec: 10, restSec: 180),
    ),
    note: 'Jede Wiederholung so schnell wie möglich.',
    source:
        'Quellen nennen 50–65 % für Schnellkraft, 2er-Gruppen mit 10 s '
        'und 3 min Satzpause; die genaue Aufteilung ist eigene Festlegung.',
  ),
];
