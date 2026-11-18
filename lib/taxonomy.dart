/// Baukasten: vorbelegte Schlagworte. Eigene Schlagworte kommen in der App
/// dazu, sobald sie an einer Übung verwendet werden.
const defaultGoals = [
  'Maximalkraft',
  'Hypertrophie',
  'Schnellkraft',
  'Kraftausdauer',
  'Stabilität',
  'Beweglichkeit',
  'Aktivierung',
  'Technik',
  'Prävention',
  'Reha',
  'Regeneration',
];

const defaultEquipment = [
  'Körpergewicht',
  'Langhantel',
  'Kurzhantel',
  'Kettlebell',
  'Band',
  'Kabelzug',
  'Maschine',
  'Klimmzugstange',
  'Bank',
  'Box / Stufe',
  'Medizinball',
  'Faszienrolle',
];

/// Vorbelegung zuerst (in fester Reihenfolge), danach eigene alphabetisch.
List<String> mergeVocabulary(List<String> defaults, Iterable<String> used) {
  final extra =
      used
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty && !defaults.contains(t))
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [...defaults, ...extra];
}
