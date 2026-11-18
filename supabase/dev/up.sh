#!/usr/bin/env bash
# Startet den Test-Stack und spielt die Migration ein.
set -euo pipefail
cd "$(dirname "$0")"
python3 make_env.py
set -a; . ./.env; set +a

psql_db() { docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "${1:-postgres}" -d postgres -q "${@:2}"; }

docker compose up -d db
echo "warte auf Datenbank ..."
until docker compose exec -T db pg_isready -U postgres -h localhost >/dev/null 2>&1; do sleep 2; done
# Das Image startet Postgres während der Initialisierung einmal neu.
sleep 5
until docker compose exec -T db psql -U postgres -d postgres -c "select 1" >/dev/null 2>&1; do sleep 2; done

# Passwörter der Dienst-Rollen setzen (macht im offiziellen Compose roles.sql).
psql_db supabase_admin <<SQL
alter user authenticator with password '${POSTGRES_PASSWORD}';
alter user supabase_auth_admin with password '${POSTGRES_PASSWORD}';
alter user supabase_storage_admin with password '${POSTGRES_PASSWORD}';
SQL

docker compose up -d
echo "warte auf Auth, REST und Storage ..."
for i in $(seq 1 60); do
  a=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:54321/auth/v1/health || true)
  r=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:54321/rest/v1/ -H "apikey: ${ANON_KEY}" || true)
  s=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:54321/storage/v1/status || true)
  [ "$a" = 200 ] && [ "$r" = 200 ] && [ "$s" = 200 ] && break
  sleep 2
done
echo "auth=$a rest=$r storage=$s"

psql_db postgres < ../migrations/0001_coachplan.sql
echo "Migration eingespielt."
echo "URL:      http://localhost:54321"
echo "ANON_KEY: ${ANON_KEY}"
