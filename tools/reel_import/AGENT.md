# Reel-Import: Anleitung für den Agenten auf dem Homelab

Du importierst Trainingsvideos (Instagram-Reels, YouTube-Shorts, TikTok …)
in die Übungsbibliothek der CoachPlan-App. Pro Link entstehen ein **Clip**
(Link, Beschreibung, Transkript, Standbilder) und daraus abgeleitete
**Übungen**. Der Trainer sieht beides nach dem nächsten Abgleich in der App;
die Übungen tragen die Marke „Prüfen“, bis er sie durchgesehen und
gespeichert hat.

Deine Aufgabe ist der Teil, den kein Skript kann: aus Transkript,
Beschreibung und Standbildern die Übungen herauslesen und sauber
beschreiben.

## Stand

Hier im Repo getestet: Standbilder, Prüfung von `exercises.json`, der Aufruf
einer LLM-Schnittstelle (gegen eine Attrappe), Upload und das Erscheinen in
der App.

**Noch nie echt gelaufen** – auf der Entwicklungsumgebung waren Instagram,
YouTube und Hugging Face gesperrt:

- der Download mit yt-dlp,
- die Transkription mit Whisper (Modell-Download von Hugging Face),
- die Auswertung durch ein echtes Sprachmodell.

Prüfe diese drei beim Einrichten (Schritt 3) und melde das Ergebnis.

## Einmalig einrichten

1. Voraussetzungen: `python3` (ab 3.10) und `ffmpeg`.
2. Im Ordner `tools/reel_import`:

   ```bash
   ./setup.sh
   ```

   Legt `.venv` an, installiert yt-dlp und faster-whisper, erzeugt `.env`
   aus `.env.example` und zeigt den Zustand. Danach `.env` ausfüllen:
   Adresse und `anon key` des CoachPlan-Servers sowie E-Mail und Passwort
   des **Trainer-Kontos**, in dessen Bibliothek importiert wird.
   Die Datei enthält ein Passwort: nicht einchecken (steht in `.gitignore`),
   Rechte `600`, niemandem anzeigen.
3. Prüfen:

   ```bash
   .venv/bin/python reel_import.py doctor --model small
   ```

   Lädt das Whisper-Modell (einmalig, einige hundert MB) und meldet sich am
   Server an. Dann einen echten Probelauf mit einem kurzen, öffentlichen
   Video machen (`fetch`, siehe unten) und nachsehen, ob `transcript.txt`
   brauchbar ist.

## Ablauf pro Link

Alle Befehle: `.venv/bin/python reel_import.py <befehl>`.

### 1. Holen

```bash
.venv/bin/python reel_import.py fetch "<link>"
```

Erzeugt `imports/<clip-id>/` mit

- `result.json` – Titel, Beschreibung (`caption`), Urheber, Transkript mit
  Zeitmarken, Liste der Standbilder mit Zeitpunkt,
- `transcript.txt` – das Transkript zum Lesen,
- `frames/00.jpg …` – Standbilder, gleichmäßig über das Video verteilt,
- `video.mp4` – bleibt nur lokal und wird nie hochgeladen.

Nützliche Optionen: `--language de`, `--model medium` (genauer, langsamer),
`--frames 10`, `--file video.mp4` (vorhandene Datei statt Download; der Link
wird trotzdem als Quelle gespeichert), `--delete-video`.

Derselbe Link ergibt immer dieselbe `clip-id`, auch mit anderen
Tracking-Anhängseln.

### 2. Übungen beschreiben

Lies `result.json` und sieh dir – wenn du Bilder ansehen kannst – die
Standbilder an. Schreibe dann `imports/<clip-id>/exercises.json`:

```json
{
  "exercises": [
    {
      "name": "Cossack Squat",
      "category": "mobility",
      "bodyRegion": "Hüfte / Adduktoren",
      "goals": ["Beweglichkeit"],
      "equipment": ["Körpergewicht"],
      "description": "Tief zur Seite absitzen, die Ferse bleibt am Boden.",
      "whenToUse": "Vor dem Beintraining, 8 Wiederholungen je Seite.",
      "frames": [3, 4]
    }
  ]
}
```

| Feld | Bedeutung |
| --- | --- |
| `name` | Name der Übung, wie ein Trainer sie nennen würde |
| `category` | `kraft`, `physio` oder `mobility` |
| `bodyRegion` | Körperregion oder Muskelgruppe |
| `goals` | Ziel-Schlagworte, bevorzugt aus `taxonomy.json` |
| `equipment` | Geräte, bevorzugt aus `taxonomy.json` |
| `description` | Coach-Hinweise zur Ausführung, knapp, auf Deutsch |
| `whenToUse` | Wofür und wann die Übung eingesetzt wird |
| `frames` | Nummern der Standbilder, die diese Übung zeigen (höchstens 4) |

Regeln:

- **Nichts erfinden.** Nur aufnehmen, was Transkript, Beschreibung oder
  Bilder hergeben. Fehlt etwas, das Feld leer lassen – der Trainer ergänzt.
  Eine falsche Ausführungsanweisung ist schlimmer als eine fehlende.
- Zeigt das Video mehrere Übungen, dann ein Eintrag je Übung.
- Zeigt es keine erkennbare Übung: `{"exercises": []}`. Der Clip wird dann
  ohne Übungen angelegt.
- Reels ohne gesprochenen Text sind häufig (nur Musik). Das Transkript ist
  dann leer oder enthält Liedtext; verlass dich auf Beschreibung und Bilder.
- Kannst du keine Bilder ansehen, ordne `frames` über die Zeitpunkte zu
  (Standbild bei 0:14 passt zum Transkript-Abschnitt um 0:14) oder lass die
  Liste leer.
- Neue Schlagworte sind erlaubt, wenn keines aus `taxonomy.json` passt.

Prüfen:

```bash
.venv/bin/python reel_import.py validate imports/<clip-id>
```

### 3. Hochladen

```bash
.venv/bin/python reel_import.py upload imports/<clip-id>
```

Lädt die Standbilder hoch, legt den Clip und die Übungen an. Ein zweiter
Lauf ändert nichts an vorhandenen Einträgen – so bleibt erhalten, was der
Trainer in der App schon überarbeitet hat. `--overwrite` ersetzt sie; nur
verwenden, wenn der Trainer das ausdrücklich will.

### Ohne Agent: alles in einem Schritt

Ist in `.env` eine OpenAI-kompatible Chat-Schnittstelle eingetragen
(`LLM_URL`, `LLM_MODEL`, optional `LLM_API_KEY`), erledigt

```bash
.venv/bin/python reel_import.py run "<link>"
```

Holen, Auswerten und Hochladen nacheinander. Das Modell bekommt dabei nur
Text (Titel, Beschreibung, Transkript, Zeitpunkte der Standbilder), keine
Bilder. Für Reels ohne gesprochenen Text ist der Weg über den Agenten
besser.

## Wenn etwas nicht geht

- **Download verlangt Anmeldung** (v. a. Instagram): Das ist eine
  Entscheidung des Trainers, weil sein Konto dadurch eingeschränkt werden
  kann. Nicht selbst Zugangsdaten suchen oder einsetzen. Erst wenn er eine
  Cookie-Datei bereitstellt: `--cookies <datei>` bzw. `YTDLP_COOKIES` in
  `.env`. Bis dahin: Video von Hand speichern lassen und `--file` nutzen.
- **Download scheitert aus anderem Grund:** einmal `pip install -U yt-dlp`
  in der `.venv` versuchen (Plattformen ändern sich oft), dann melden.
  Nicht in einer Schleife wiederholen.
- **Mehrere Links:** nacheinander mit Pause, nicht parallel.
- **Whisper zu langsam:** kleineres Modell (`base`) oder GPU
  (`WHISPER_DEVICE=cuda`, `WHISPER_COMPUTE=float16`).

## Grenzen

- Videos werden nicht in die App geladen; dort steht der Link zum Original.
  Die Videodatei in `imports/` ist eine lokale Arbeitskopie.
- Nur Links importieren, die der Trainer dir gibt.
- Nach jedem Import kurz melden: Titel, gefundene Übungen, was unklar war.
