/// Grundlagen für geschwindigkeitsbasiertes Training (VBT).
/// Geschwindigkeit ist immer die mittlere Geschwindigkeit der
/// konzentrischen Phase in m/s.
library;

/// Mittlere Geschwindigkeit aus einer Zeitlupen-Aufnahme: Weg der Hantel
/// geteilt durch die Dauer zwischen Start- und Endbild der Aufwärtsbewegung.
/// [romM] ist der einmal gemessene Hubweg in Metern.
double? velocityFromFrames({
  required double romM,
  required int startFrame,
  required int endFrame,
  required double fps,
}) {
  final frames = endFrame - startFrame;
  if (romM <= 0 || frames <= 0 || fps <= 0) return null;
  return romM / (frames / fps);
}

/// Größter Fehler der Messung durch die Bildrate: je ein Bild Unsicherheit
/// an Start und Ende, als Anteil (0.04 = 4 %).
double frameCountingError({required double durationSec, required double fps}) {
  if (durationSec <= 0 || fps <= 0) return double.infinity;
  return (2 / fps) / durationSec;
}

/// Geschwindigkeitsverlust im Satz gegenüber der schnellsten Wiederholung,
/// als Anteil (0.2 = 20 %).
double? velocityLoss(List<double> repVelocities) {
  if (repVelocities.isEmpty) return null;
  final best = repVelocities.reduce((a, b) => a > b ? a : b);
  if (best <= 0) return null;
  return 1 - repVelocities.last / best;
}

/// Bereiche nach Bryan Mann (mittlere Geschwindigkeit). Die Grenzen sind
/// Richtwerte und überlappen in der Praxis.
enum VelocityZone {
  absolutkraft('Maximalkraft', 0, 0.5),
  beschleunigungskraft('Beschleunigungskraft', 0.5, 0.75),
  kraftSchnelligkeit('Kraft-Schnelligkeit', 0.75, 1.0),
  schnellkraft('Schnellkraft', 1.0, 1.3),
  startkraft('Startkraft', 1.3, double.infinity);

  const VelocityZone(this.label, this.from, this.to);

  final String label;
  final double from;
  final double to;

  static VelocityZone of(double v) =>
      values.firstWhere((z) => v < z.to, orElse: () => startkraft);
}

/// Schätzt das 1RM aus zwei Messungen (leichte und schwere Last) über die
/// Last-Geschwindigkeits-Gerade: die Last, bei der die Geschwindigkeit auf
/// [mvt] fällt (Geschwindigkeit beim 1RM; in der Literatur etwa 0,30 m/s
/// für die Kniebeuge und 0,15 m/s für das Bankdrücken, individuell
/// verschieden).
double? oneRmFromTwoPoints({
  required double lightKg,
  required double lightVelocity,
  required double heavyKg,
  required double heavyVelocity,
  required double mvt,
}) {
  if (heavyKg <= lightKg || lightVelocity <= heavyVelocity) return null;
  if (mvt <= 0 || mvt >= heavyVelocity) return null;
  final slope = (heavyVelocity - lightVelocity) / (heavyKg - lightKg);
  return lightKg + (mvt - lightVelocity) / slope;
}
