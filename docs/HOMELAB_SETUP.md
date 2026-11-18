# CoachPlan-Backend auf dem Homelab einrichten

Übergabe an den Agenten (oder Menschen), der Zugriff auf das Homelab hat.
Ziel: Die CoachPlan-App spricht mit einem selbst gehosteten Supabase, das
über Cloudflare per HTTPS aus dem Internet erreichbar ist.

**Stand dieses Repos:** App, Datenbank-Migration und Prüfskripte sind fertig
und gegen einen lokalen Supabase-Stack getestet (Auth `gotrue v2.198.0`,
`postgrest v14.18`, `storage-api v1.97.1`, `supabase/postgres 15.20.0.001`).
Auf dem Homelab selbst wurde noch nichts eingerichtet oder geprüft.

## Was am Ende stehen muss

1. Ein Supabase mit Auth, REST (PostgREST) und Storage läuft dauerhaft.
2. Die Migration `supabase/migrations/0001_coachplan.sql` ist eingespielt.
3. Eine öffentliche HTTPS-Adresse (z. B. `https://coachplan.<domain>`) führt
   auf das Supabase-API-Gateway – und nur auf die drei API-Pfade.
4. `supabase/smoke_test.sh` läuft gegen diese Adresse fehlerfrei durch.
5. Zurückgemeldet werden: die öffentliche Adresse und der `anon key`.

## 1. Supabase

Zuerst prüfen, ob auf dem Homelab schon ein Supabase läuft
(`docker ps | grep -i supabase`). Wenn ja: wiederverwenden, weiter bei
Schritt 2.

Sonst das **offizielle** Docker-Setup verwenden, nicht
`supabase/dev/docker-compose.yml` aus diesem Repo (das ist ein abgespeckter
Test-Stack ohne Kong, Studio und Realtime):

- Anleitung: <https://supabase.com/docs/guides/self-hosting/docker>
- Die Anleitung ist maßgeblich. Die folgenden Variablennamen stammen aus der
  `.env.example` des offiziellen Setups, wie sie beim Schreiben bekannt war –
  bitte gegen die aktuelle Datei prüfen.

Zu setzen (alle Geheimnisse neu erzeugen, keine Beispielwerte übernehmen):

| Variable | Wert |
| --- | --- |
| `POSTGRES_PASSWORD` | langes Zufallspasswort |
| `JWT_SECRET` | mind. 32 Zeichen Zufall |
| `ANON_KEY`, `SERVICE_ROLE_KEY` | JWTs, mit `JWT_SECRET` signiert (Rollen `anon` / `service_role`), laut Anleitung erzeugen |
| `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` | Zugang zum Studio |
| `SITE_URL`, `API_EXTERNAL_URL`, `SUPABASE_PUBLIC_URL` | die öffentliche Adresse aus Schritt 3 |
| `ENABLE_EMAIL_SIGNUP` | `true` |
| `ENABLE_EMAIL_AUTOCONFIRM` | `true`, solange kein SMTP eingerichtet ist (siehe unten) |
| `DISABLE_SIGNUP` | `false` (siehe „Offene Entscheidungen“) |

**E-Mail-Bestätigung:** Die App meldet nach der Registrierung sofort an.
Ohne SMTP muss `ENABLE_EMAIL_AUTOCONFIRM=true` gesetzt sein, sonst liefert
die Registrierung keine Sitzung (das Prüfskript meldet das ausdrücklich).
Mit SMTP kann die Bestätigung eingeschaltet werden; die App zeigt dann
„Bitte die E-Mail bestätigen und dann anmelden“.

Der `SERVICE_ROLE_KEY` umgeht alle Zugriffsregeln. Er bleibt auf dem Server
und gehört weder in die App noch in dieses Repo.

## 2. Migration einspielen

Erst wenn Auth und Storage gestartet sind (die Migration legt einen Trigger
auf `auth.users` und Regeln auf `storage.objects` an):

```bash
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < supabase/migrations/0001_coachplan.sql
```

Container- und Dienstname (`db`) ggf. an das offizielle Compose anpassen.
Das Skript ist wiederholbar; „does not exist, skipping“-Hinweise beim ersten
Lauf sind normal.

Kontrolle:

```bash
docker compose exec -T db psql -U postgres -d postgres -Atc "
  select string_agg(tablename, ',' order by tablename) from pg_tables
   where schemaname = 'public'
     and tablename in ('profiles','athletes','exercises','clips','sessions');
  select count(*) from pg_policies where schemaname = 'public';
  select id, public from storage.buckets where id = 'media';"
```

Erwartet: `athletes,clips,exercises,profiles,sessions`, `10`, `media|f`.

### Was die Migration anlegt

- `profiles` (Rolle `coach`/`athlete`, automatisch bei der Registrierung)
- `athletes`, `exercises`, `clips`, `sessions`: je Trainer (`coach_id`),
  Inhalt als JSON in `data`; bei `sessions` zusätzlich `log` (Protokoll des
  Athleten). Gelöschtes bleibt als Zeile mit `deleted = true` stehen.
- Zugriffsregeln (RLS): Der Trainer sieht und ändert nur Eigenes. Ein
  verknüpfter Athlet liest seine Einheiten und die Übungen seines Trainers
  und darf an seinen Einheiten ausschließlich `log` ändern (per Trigger
  erzwungen). Clips sieht nur der Trainer.
- Einladungen: `create_invite` (Trainer) und `redeem_invite` (Athlet).
- Privater Storage-Bucket `media`, Pfad `<coach_id>/<bild_id>`.

## 3. Cloudflare

Einen Cloudflare Tunnel (`cloudflared`) auf das Kong-Gateway des
Supabase-Stacks legen (im offiziellen Compose Port `8000`).

- **Nur die API-Pfade freigeben:** `/auth/v1/*`, `/rest/v1/*`,
  `/storage/v1/*`. Alles andere (insbesondere das Studio unter `/` und der
  Postgres-Port) bleibt intern bzw. hinter Cloudflare Access.
- **Kein Cloudflare Access vor den drei API-Pfaden:** Die App schickt nur
  `apikey` und das Nutzer-Token; eine vorgeschaltete Anmeldeseite würde sie
  aussperren.
- HTTPS ist Pflicht: Android und iOS blockieren unverschlüsseltes HTTP in
  Release-Builds.
- Upload-Grenze von Cloudflare beachten; die App lädt nur verkleinerte
  Bilder (max. 1600 px Kantenlänge) hoch.
- WAF/Bot-Schutz so einstellen, dass normale API-Aufrufe (JSON, kein
  Browser) nicht mit einer Challenge beantwortet werden.

Beispiel für `cloudflared` (`config.yml`), Namen anpassen:

```yaml
ingress:
  - hostname: coachplan.example.org
    path: ^/(auth|rest|storage)/v1/.*
    service: http://localhost:8000
  - service: http_status:404
```

## 4. Abnahme

Von einem Rechner außerhalb des Heimnetzes (oder über die öffentliche
Adresse):

```bash
SUPABASE_URL=https://coachplan.example.org ANON_KEY=<anon key> \
  ./supabase/smoke_test.sh
```

Das Skript braucht nur `curl` und `python3`. Es legt zwei Test-Konten an und
prüft Erreichbarkeit, Registrierung, Zugriffsregeln, Einladung und
Bild-Upload. Alle Zeilen müssen mit `OK` beginnen. Danach aufräumen:

```sql
delete from auth.users where email like 'smoke-%@example.com';
```

Zusätzlich prüfen: `https://coachplan.example.org/` (ohne API-Pfad) darf das
Studio **nicht** zeigen.

Optional, falls Flutter vorhanden ist, der vollständige Test der
App-Synchronisation (zwei simulierte Geräte):

```bash
COACHPLAN_TEST_URL=https://coachplan.example.org \
COACHPLAN_TEST_ANON_KEY=<anon key> \
  flutter test test/integration
```

## 5. Betrieb

- **Backup:** regelmäßig `pg_dump` der Datenbank und das Storage-Volume
  sichern (dort liegen die Bilder). Eine Rücksicherung einmal ausprobieren.
- **Updates:** Supabase-Images gelegentlich nach offizieller Anleitung
  aktualisieren; danach `smoke_test.sh` erneut laufen lassen.
- **Daten:** Es werden Trainings- und teils Gesundheitsangaben gespeichert
  (Verletzungen, Belastung, Rückmeldungen). Zugriff auf Server und Studio
  entsprechend eng halten.

## 6. App mit dem Server verbinden

Die Server-Adresse wird beim Bauen mitgegeben, dann müssen Trainer und
Athleten nichts eintippen:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://coachplan.example.org \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Ohne diese Angaben fragt die App unter „Konto & Sync“ nach Adresse und
Schlüssel. Der `anon key` ist kein Geheimnis (er steckt in jeder App);
den Schutz leisten die Zugriffsregeln.

Ablauf danach: Trainer registriert sich in der App („Trainer“), legt einen
Athleten an und erzeugt dort unter „App-Zugang“ einen Einladungscode. Der
Athlet registriert sich als „Athlet“ und gibt den Code ein.

## Offene Entscheidungen (bitte an Juan zurückgeben, nicht selbst festlegen)

1. **Registrierung offen lassen?** Solange `DISABLE_SIGNUP=false` ist, kann
   sich jeder, der die Adresse kennt, ein Konto anlegen. Fremde sehen keine
   Daten, belegen aber Platz. Möglich: nach dem Einrichten aller Konten auf
   `true` stellen und für neue Athleten kurz öffnen.
2. **SMTP** für E-Mail-Bestätigung und „Passwort vergessen“ (die App hat
   dafür noch keine Funktion).
3. **Verteilung der App** an Athleten (APK, TestFlight, oder die Web-Version
   über das Homelab ausliefern).

## Reel-Import (optional, nach der Abnahme)

Werkzeug zum Importieren von Reels/Shorts in die Übungsbibliothek:
`tools/reel_import/`. Einrichtung und Ablauf stehen in
[`tools/reel_import/AGENT.md`](../tools/reel_import/AGENT.md). Es läuft auf
dem Homelab (nicht im Supabase-Stack), braucht `python3`, `ffmpeg` und die
Zugangsdaten des Trainer-Kontos.
