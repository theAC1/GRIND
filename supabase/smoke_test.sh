#!/usr/bin/env bash
# Prüft ein Supabase mit eingespielter CoachPlan-Migration von außen, nur
# mit curl. Legt zwei Test-Konten an (smoke-…@example.com).
#
#   SUPABASE_URL=https://coachplan.example.org ANON_KEY=… ./smoke_test.sh
set -uo pipefail
: "${SUPABASE_URL:?SUPABASE_URL fehlt}" "${ANON_KEY:?ANON_KEY fehlt}"
U="${SUPABASE_URL%/}"
RUN="$(date +%s)$RANDOM"
fail=0
ok()   { echo "OK    $1"; }
bad()  { echo "FEHLER $1"; fail=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (erwartet: $3, erhalten: $2)"; fi; }
json() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
api() { # api METHODE PFAD TOKEN [DATEN] [Zusatz-Header]
  curl -sS -m 20 -X "$1" "$U$2" -H "apikey: $ANON_KEY" -H "Authorization: Bearer ${3:-$ANON_KEY}" \
    -H "Content-Type: application/json" ${5:+-H "$5"} ${4:+-d "$4"}
}
code() { curl -sS -m 20 -o /dev/null -w '%{http_code}' "$@"; }

check "Auth erreichbar"    "$(code "$U/auth/v1/health" -H "apikey: $ANON_KEY")" 200
check "REST erreichbar"    "$(code "$U/rest/v1/" -H "apikey: $ANON_KEY")" 200
check "Storage erreichbar" "$(code "$U/storage/v1/status" -H "apikey: $ANON_KEY")" 200

check "ohne Anmeldung kein Lesezugriff" \
  "$(api GET '/rest/v1/exercises?select=id' '' | json "d.get('code')")" 42501

signup() { api POST /auth/v1/signup '' "{\"email\":\"smoke-$1-$RUN@example.com\",\"password\":\"smoke-$RUN-pw\",\"data\":{\"role\":\"$1\",\"display_name\":\"Smoke $1\"}}"; }
C="$(signup coach)";   CT="$(echo "$C" | json "d['access_token']")"; CID="$(echo "$C" | json "d['user']['id']")"
A="$(signup athlete)"; AT="$(echo "$A" | json "d['access_token']")"
if [ -z "$CT" ] || [ -z "$AT" ]; then
  bad "Registrierung liefert keine Sitzung – E-Mail-Bestätigung aktiv? (ENABLE_EMAIL_AUTOCONFIRM bzw. SMTP prüfen)"
  echo "$C" | head -c 300; echo; exit 1
fi
ok "Registrierung Trainer und Athlet"
check "Profil wird automatisch angelegt" \
  "$(api GET '/rest/v1/profiles?select=role' "$CT" | json "d[0]['role']")" coach

api POST /rest/v1/athletes "$CT" "{\"coach_id\":\"$CID\",\"id\":\"smoke\",\"data\":{\"name\":\"Smoke\"}}" >/dev/null
api POST /rest/v1/sessions "$CT" "{\"coach_id\":\"$CID\",\"id\":\"s1\",\"athlete_id\":\"smoke\",\"data\":{\"title\":\"Plan\"}}" >/dev/null
check "Trainer liest eigene Einheit" \
  "$(api GET '/rest/v1/sessions?select=id' "$CT" | json "len(d)")" 1
check "Athlet sieht ohne Einladung nichts" \
  "$(api GET '/rest/v1/sessions?select=id' "$AT" | json "len(d)")" 0

INV="$(api POST /rest/v1/rpc/create_invite "$CT" '{"p_athlete_id":"smoke"}' | json "d")"
check "Einladungscode hat 10 Zeichen" "${#INV}" 10
api POST /rest/v1/rpc/redeem_invite "$AT" "{\"p_code\":\"$INV\"}" >/dev/null
check "Athlet sieht nach Einlösen seine Einheit" \
  "$(api GET '/rest/v1/sessions?select=id' "$AT" | json "d[0]['id']")" s1

api PATCH "/rest/v1/sessions?id=eq.s1" "$AT" '{"data":{"title":"manipuliert"},"log":{"done":true}}' >/dev/null
ROW="$(api GET '/rest/v1/sessions?select=data,log' "$CT")"
check "Athlet kann den Plan nicht ändern" "$(echo "$ROW" | json "d[0]['data']['title']")" Plan
check "Athlet kann das Protokoll schreiben" "$(echo "$ROW" | json "d[0]['log']['done']")" True

UP="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X POST "$U/storage/v1/object/media/$CID/smoke.jpg" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CT" -H "Content-Type: image/jpeg" --data-binary 'x')"
check "Trainer lädt Bild hoch" "$UP" 200
check "Athlet liest Bild des Trainers" \
  "$(code "$U/storage/v1/object/media/$CID/smoke.jpg" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $AT")" 200
NOAUTH="$(code "$U/storage/v1/object/media/$CID/smoke.jpg" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")"
if [ "$NOAUTH" != 200 ]; then ok "Bild ohne Anmeldung gesperrt"; else bad "Bild ohne Anmeldung lesbar"; fi

echo
if [ "$fail" = 0 ]; then echo "Alle Prüfungen bestanden."; else echo "Es gab Fehler."; fi
echo "Aufräumen (SQL): delete from auth.users where email like 'smoke-%@example.com';"
exit "$fail"
