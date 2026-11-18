import 'models.dart';

/// Startbestand der Übungsbibliothek. Alles ist in der App editier-/löschbar.
/// Zeilenformat: Kategorie | Name | Körperregion | Ziele | Equipment | Hinweis
const _seed = '''
k|Kniebeuge|Beine|Maximalkraft,Hypertrophie|Langhantel|Langhantel auf dem oberen Rücken, Knie in Richtung der Zehen, Rumpf stabil.
k|Kreuzheben|Hintere Kette|Maximalkraft|Langhantel|Hantel nah am Körper führen, Rücken neutral, aus Hüfte und Beinen strecken.
k|Rumänisches Kreuzheben|Hintere Kette|Hypertrophie,Prävention|Langhantel|Hüfte nach hinten schieben, Knie leicht gebeugt, Dehnung im Beinbeuger.
k|Bankdrücken|Brust|Maximalkraft,Hypertrophie|Langhantel,Bank|Schulterblätter zusammen und nach unten, Hantel kontrolliert zur Brust.
k|Liegestütz|Brust|Kraftausdauer|Körpergewicht|Körper als Linie, Ellbogen ca. 45° zum Körper.
k|Schulterdrücken|Schulter|Hypertrophie|Kurzhantel|Hantel(n) über Kopf drücken, Rumpf fest, kein Hohlkreuz.
k|Klimmzug|Rücken|Maximalkraft,Hypertrophie|Klimmzugstange|Aus dem Hang mit Schulterblatt-Zug beginnen, Kinn über die Stange.
k|Langhantelrudern|Rücken|Hypertrophie|Langhantel|Oberkörper vorgebeugt, Hantel zum Bauchnabel ziehen.
k|Ausfallschritte|Beine|Hypertrophie,Stabilität|Kurzhantel|Großer Schritt, vorderes Knie über dem Fuß, Oberkörper aufrecht.
k|Hip Thrust|Gesäß|Hypertrophie,Schnellkraft|Langhantel,Bank|Oberer Rücken auf der Bank, Hüfte bis zur vollen Streckung anheben.
k|Wadenheben|Unterschenkel|Hypertrophie|Box / Stufe|Voller Bewegungsumfang, oben kurz halten.
k|Unterarmstütz (Plank)|Rumpf|Stabilität|Körpergewicht|Ellbogen unter den Schultern, Becken neutral, Position halten.
p|Außenrotation Schulter (Theraband)|Schulter|Prävention,Reha|Band|Ellbogen am Körper, Unterarm gegen Bandwiderstand nach außen drehen.
p|Band Pull-Apart|Schulter|Prävention,Aktivierung|Band|Band auf Brusthöhe auseinanderziehen, Schulterblätter zusammenführen.
p|Clamshell|Hüfte|Aktivierung,Reha|Band|Seitlage, Füße zusammen, oberes Knie öffnen ohne das Becken zu drehen.
p|Seitliches Beinheben|Hüfte|Aktivierung,Reha|Körpergewicht|Seitlage, gestrecktes oberes Bein leicht nach hinten-oben anheben.
p|Glute Bridge|Gesäß|Aktivierung,Reha|Körpergewicht|Rückenlage, Füße aufgestellt, Becken anheben bis Hüfte gestreckt ist.
p|Bird Dog|Rumpf|Stabilität,Reha|Körpergewicht|Vierfüßlerstand, Arm und Gegenbein strecken, Rumpf ruhig halten.
p|Dead Bug|Rumpf|Stabilität,Reha|Körpergewicht|Rückenlage, Lendenwirbelsäule am Boden, Arm und Gegenbein absenken.
p|Exzentrisches Wadenheben|Achillessehne|Reha,Prävention|Box / Stufe|Beidbeinig hoch, einbeinig langsam (ca. 3–4 s) über die Stufenkante absenken.
p|Terminal Knee Extension|Knie|Reha,Aktivierung|Band|Band in der Kniekehle, Knie gegen Widerstand vollständig strecken.
p|Nordic Hamstring Curl|Oberschenkel hinten|Prävention|Körpergewicht|Füße fixiert, Oberkörper langsam und kontrolliert nach vorn absenken.
p|Copenhagen Plank|Adduktoren|Prävention,Stabilität|Bank|Seitstütz, oberes Bein auf der Bank, Becken oben halten.
p|Einbeinstand|Sprunggelenk|Stabilität,Reha|Körpergewicht|Auf einem Bein stehen, Becken gerade; Steigerung: instabile Unterlage.
m|Katze-Kuh|Wirbelsäule|Beweglichkeit,Aktivierung|Körpergewicht|Vierfüßlerstand, Wirbelsäule abwechselnd runden und strecken.
m|Hüftbeuger-Dehnung|Hüfte|Beweglichkeit|Körpergewicht|Halber Kniestand, Becken aufrichten und nach vorn schieben.
m|90/90 Hüftrotation|Hüfte|Beweglichkeit|Körpergewicht|Im Sitz beide Knie 90° gebeugt, kontrolliert von Seite zu Seite rotieren.
m|BWS-Rotation|Brustwirbelsäule|Beweglichkeit|Körpergewicht|Seitlage oder Vierfüßler, Oberkörper aufdrehen, Blick folgt der Hand.
m|Sprunggelenk-Mobilisation|Sprunggelenk|Beweglichkeit,Reha|Körpergewicht|Knie-zur-Wand: Ferse bleibt am Boden, Knie über die Zehen schieben.
m|World's Greatest Stretch|Ganzkörper|Beweglichkeit,Aktivierung|Körpergewicht|Ausfallschritt, Ellbogen zum Boden, dann Arm zur Decke aufdrehen.
''';

List<Exercise> seedExercises() {
  const categories = {
    'k': ExerciseCategory.kraft,
    'p': ExerciseCategory.physio,
    'm': ExerciseCategory.mobility,
  };
  final lines = _seed.trim().split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      () {
        final f = lines[i].split('|');
        return Exercise(
          id: 'seed_$i',
          category: categories[f[0]]!,
          name: f[1],
          bodyRegion: f[2],
          goals: f[3].split(','),
          equipment: f[4].split(','),
          description: f[5],
        );
      }(),
  ];
}
