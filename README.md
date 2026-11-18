# CoachPlan

Flutter-App für Trainer: Athleten verwalten, Übungsbibliothek (Kraft, Physio,
Mobility) mit Videos und Bildern pflegen, Trainingseinheiten planen und vom
Athleten Satz für Satz abhaken lassen.

## Funktionen

- **Plan**: Tagesübersicht, anstehende/vergangene Einheiten, Fortschritt je
  Einheit (abgehakte Sätze)
- **Einheit planen**: Athlet, Datum, Übungen per Mehrfachauswahl, Vorgabe je
  Übung (Sätze, Wdh./Dauer, Gewicht in kg, Widerstand, Pause, Coach-Hinweis)
- **Trainingsmodus (Athlet)**: Übung für Übung; ein Tipp hakt einen Satz wie
  vorgegeben ab, „Alle wie geplant“ die ganze Übung. Gewicht und
  Wiederholungen per −/+ oder Direkteingabe; ein geändertes Gewicht gilt
  automatisch für die folgenden offenen Sätze. Abschluss mit RPE (1–10) und
  Rückmeldung an den Coach. Jeder Tipp wird sofort gespeichert.
- **Übungen**: Videos (Links zu YouTube, Instagram, TikTok …), Bilder,
  Coach-Hinweise, „Wann einsetzen“, Baukasten-Schlagworte für Ziel und
  Equipment (vorbelegt, um eigene erweiterbar), Suche und Ziel-Filter
- **Clips**: Sammlung gespeicherter Reel-/Short-Links mit Notizen/Transkript
  und Screenshots; aus einem Clip lassen sich mehrere Übungen ableiten
- **Bereitstellen**: Einheit als Text inkl. Video-Links teilen oder kopieren,
  auf andere Athleten/Tage duplizieren

## Farbkonzept „Tartan & Graphit“

| Rolle | Farbe | Einsatz |
| --- | --- | --- |
| Graphit | `#15191C` | Kopfleiste, Text, ausgewählte Zustände |
| Tartan | `#C8401C` (dunkel: `#FF7A50`) | einzige Signalfarbe: Aktionen, Fortschritt |
| Papier | `#F5F4F0` | Hintergrund, warmes Off-White |
| Kraft | `#2F5F9E` | Stahlblau |
| Physio | `#1E8A6E` | Grün |
| Mobility | `#A9741A` | Ocker |
| Erledigt | `#2E7D4F` | abgehakte Sätze, erledigte Einheiten |

Überschriften und Zahlen in Barlow Condensed (SIL OFL 1.1, siehe
`assets/fonts/LICENSE.txt`). Helles und dunkles Design, definiert in
`lib/theme.dart`.

## Konto, Sync und Athleten-Zugang

Mit einem Supabase-Server (selbst gehostet, siehe
[docs/HOMELAB_SETUP.md](docs/HOMELAB_SETUP.md)) kommen dazu:

- **Konten** für Trainer und Athleten (E-Mail + Passwort)
- **Abgleich** zwischen Geräten: Die App arbeitet weiter lokal und ohne Netz;
  Änderungen werden hochgeladen, sobald der Server erreichbar ist
  (automatisch nach jeder Änderung, beim Öffnen der App und alle 45 s).
- **Athleten-Zugang** per Einladungscode: Der Athlet sieht in seiner App nur
  seine Einheiten samt Übungen, Videos und Bildern und hakt dort ab. Er kann
  ausschließlich sein Protokoll ändern; der Server erzwingt das.
- Plan (Trainer) und Protokoll (Athlet) einer Einheit werden getrennt
  abgeglichen und überschreiben sich nicht gegenseitig. Ändern zwei Geräte
  dasselbe Objekt, gilt die zuletzt hochgeladene Fassung.

Ohne Server bleibt alles wie bisher rein lokal.

## Grenzen

- **Ein Trainer je Athleten-Konto.** Ein Athlet kann derzeit nur mit einem
  Trainer verknüpft sein.
- **Kein „Passwort vergessen“** in der App (bräuchte SMTP am Server).
- **Kein Live-Abgleich**: Änderungen des anderen erscheinen nach dem nächsten
  Abgleich (spätestens nach 45 s bei geöffneter App), nicht sofort.
- **Videos** öffnen in der jeweiligen App bzw. im Browser, nicht eingebettet.
  Vorschaubilder gibt es automatisch nur für YouTube.
- **Kein automatischer Import** von Reels (Video, Transkript, Auswertung):
  Link, Notizen und Screenshots werden von Hand erfasst.
- Im Browser landen Bilder im lokalen Speicher (wenige MB) – die Web-Version
  ist zum Ausprobieren gedacht, nicht für große Bildmengen.

## Starten

```bash
flutter pub get
flutter run            # Gerät/Emulator
flutter run -d chrome  # Browser
flutter test
```

Mit Server-Vorgabe bauen (dann fragt die App nicht nach der Adresse):

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://coachplan.example.org \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Backend lokal testen (Docker nötig): `supabase/dev/up.sh` startet einen
Test-Stack und spielt die Migration ein; danach

```bash
COACHPLAN_TEST_URL=http://localhost:54321 \
COACHPLAN_TEST_ANON_KEY=<aus supabase/dev/.env> \
  flutter test test/integration
```

Entwickelt mit Flutter 3.50.0 (Paket `material_ui`).

## Aufbau

```
lib/
  main.dart               App
  theme.dart              Farbkonzept, helles/dunkles Design
  models.dart             Athlete, Exercise, VideoClip, SessionEntry, SetLog, TrainingSession
  store.dart              AppStore (Zustand, Persistenz, Bild-Aufräumen)
  workout.dart            Logik des Trainingsprotokolls
  taxonomy.dart           Baukasten: Ziele, Equipment
  links.dart              Link-Erkennung, YouTube-Vorschaubild
  media.dart              Bildablage (Datei / Browser / Test)
  sync/                   Server-Anbindung: Anmeldung, Abgleich, Einladungen
  seed.dart               Startbestand der Übungsbibliothek
  format.dart             Datum, Vorgabe, Einheit als Text
  screens/                Home, Athleten, Übung, Clip, Einheit, Training
  widgets/                gemeinsame Bausteine, Medien, Übungs-Browser
test/                     Logik-, Sync- und Widget-Tests; integration/ gegen echten Server
supabase/
  migrations/             Datenbank-Schema und Zugriffsregeln
  smoke_test.sh           Abnahme eines Servers per curl
  dev/                    kleiner Test-Stack (nicht für den Betrieb)
docs/HOMELAB_SETUP.md     Einrichtung auf dem Homelab (Supabase, Cloudflare)
```
