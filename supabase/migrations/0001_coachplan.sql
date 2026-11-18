-- CoachPlan: Schema, Zugriffsregeln (RLS) und Speicher-Bucket.
--
-- Voraussetzung: ein laufendes Supabase (Auth, PostgREST, Storage), d. h.
-- die Schemata "auth" und "storage" existieren bereits.
-- Das Skript ist wiederholbar (idempotent).
--
-- Datenmodell: Jede Zeile gehört zu einem Trainer (coach_id). Die App hält
-- ihre Objekte als JSON in "data"; nur was für Zugriffsregeln nötig ist,
-- steht in eigenen Spalten. Gelöschte Zeilen bleiben als Markierung
-- (deleted = true) stehen, damit andere Geräte die Löschung mitbekommen.

-- ---------------------------------------------------------------------------
-- Profile
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('coach', 'athlete')),
  display_name text not null default '',
  created_at timestamptz not null default now()
);

-- Legt beim Registrieren automatisch das Profil an. Rolle und Name kommen
-- aus den Metadaten der Registrierung.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    case when new.raw_user_meta_data ->> 'role' = 'coach'
      then 'coach' else 'athlete' end,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table if not exists public.athletes (
  coach_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  data jsonb not null default '{}',
  -- Konto des Athleten, sobald er seinen Einladungscode eingelöst hat.
  user_id uuid references auth.users (id) on delete set null,
  invite_code text unique,
  invite_expires_at timestamptz,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (coach_id, id)
);

create table if not exists public.exercises (
  coach_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  data jsonb not null default '{}',
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (coach_id, id)
);

create table if not exists public.clips (
  coach_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  data jsonb not null default '{}',
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (coach_id, id)
);

create table if not exists public.sessions (
  coach_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  athlete_id text not null,
  -- Plan des Trainers (Titel, Datum, Übungen mit Vorgaben).
  data jsonb not null default '{}',
  -- Protokoll des Athleten (abgehakte Sätze, RPE, Rückmeldung).
  log jsonb not null default '{}',
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (coach_id, id)
);

create index if not exists athletes_sync_idx on public.athletes (coach_id, updated_at);
create index if not exists athletes_user_idx on public.athletes (user_id);
create index if not exists exercises_sync_idx on public.exercises (coach_id, updated_at);
create index if not exists clips_sync_idx on public.clips (coach_id, updated_at);
create index if not exists sessions_sync_idx on public.sessions (coach_id, updated_at);
create index if not exists sessions_athlete_idx on public.sessions (coach_id, athlete_id);

-- ---------------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------------

-- Änderungszeit immer vom Server, nie vom Gerät (Uhren gehen falsch).
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists athletes_touch on public.athletes;
create trigger athletes_touch before insert or update on public.athletes
  for each row execute function public.touch_updated_at();
drop trigger if exists exercises_touch on public.exercises;
create trigger exercises_touch before insert or update on public.exercises
  for each row execute function public.touch_updated_at();
drop trigger if exists clips_touch on public.clips;
create trigger clips_touch before insert or update on public.clips
  for each row execute function public.touch_updated_at();
drop trigger if exists sessions_touch on public.sessions;
create trigger sessions_touch before insert or update on public.sessions
  for each row execute function public.touch_updated_at();

-- Ein Athlet darf an seiner Einheit nur das Protokoll ändern. Alles andere
-- wird auf den bisherigen Stand zurückgesetzt, egal was das Gerät schickt.
create or replace function public.sessions_guard()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null and auth.uid() <> old.coach_id then
    new.coach_id := old.coach_id;
    new.id := old.id;
    new.athlete_id := old.athlete_id;
    new.data := old.data;
    new.deleted := old.deleted;
  end if;
  return new;
end;
$$;

drop trigger if exists sessions_guard on public.sessions;
create trigger sessions_guard before update on public.sessions
  for each row execute function public.sessions_guard();

-- Die Verknüpfung Athlet <-> Konto entsteht nur über den Einladungscode.
-- Ein Trainer kann sie lösen, aber kein fremdes Konto eintragen.
create or replace function public.athletes_guard()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null then
    return new; -- Verwaltung (service_role, SQL-Konsole)
  end if;
  if tg_op = 'INSERT' then
    new.user_id := null;
    new.invite_code := null;
    new.invite_expires_at := null;
  elsif new.user_id is distinct from old.user_id
    and new.user_id is not null
    and new.user_id <> auth.uid() then
    raise exception 'user_id kann nur per Einladungscode gesetzt werden';
  end if;
  return new;
end;
$$;

drop trigger if exists athletes_guard on public.athletes;
create trigger athletes_guard before insert or update on public.athletes
  for each row execute function public.athletes_guard();

-- ---------------------------------------------------------------------------
-- Einladungen
-- ---------------------------------------------------------------------------

-- Trainer: erzeugt einen Code für einen seiner Athleten (7 Tage gültig).
create or replace function public.create_invite(p_athlete_id text)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_code text;
begin
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  update public.athletes
    set invite_code = v_code,
        invite_expires_at = now() + interval '7 days'
    where coach_id = auth.uid() and id = p_athlete_id and not deleted;
  if not found then
    raise exception 'athlete_not_found';
  end if;
  return v_code;
end;
$$;

-- Athlet: löst den Code ein und wird mit dem Athleten-Eintrag verknüpft.
create or replace function public.redeem_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.athletes;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if exists (
    select 1 from public.athletes
    where user_id = auth.uid() and not deleted
  ) then
    raise exception 'already_linked';
  end if;
  update public.athletes
    set user_id = auth.uid(),
        invite_code = null,
        invite_expires_at = null
    where invite_code = upper(trim(p_code))
      and invite_expires_at > now()
      and user_id is null
      and not deleted
    returning * into v_row;
  if not found then
    raise exception 'invalid_code';
  end if;
  return jsonb_build_object('coach_id', v_row.coach_id, 'athlete_id', v_row.id);
end;
$$;

revoke all on function public.create_invite(text) from public, anon;
revoke all on function public.redeem_invite(text) from public, anon;
grant execute on function public.create_invite(text) to authenticated;
grant execute on function public.redeem_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Zugriffsregeln
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.athletes enable row level security;
alter table public.exercises enable row level security;
alter table public.clips enable row level security;
alter table public.sessions enable row level security;

revoke all on public.profiles, public.athletes, public.exercises,
  public.clips, public.sessions from anon;
grant select, insert, update, delete on public.profiles, public.athletes,
  public.exercises, public.clips, public.sessions to authenticated;

-- Ist der angemeldete Nutzer als Athlet mit diesem Trainer verknüpft?
-- security definer, damit die Prüfung nicht selbst wieder an RLS hängt.
create or replace function public.is_athlete_of(p_coach uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athletes
    where coach_id = p_coach and user_id = auth.uid() and not deleted
  );
$$;

-- Darf der angemeldete Nutzer diese Einheit als Athlet sehen?
create or replace function public.is_my_session(p_coach uuid, p_athlete_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athletes
    where coach_id = p_coach and id = p_athlete_id
      and user_id = auth.uid() and not deleted
  );
$$;

revoke all on function public.is_athlete_of(uuid) from public, anon;
revoke all on function public.is_my_session(uuid, text) from public, anon;
grant execute on function public.is_athlete_of(uuid) to authenticated;
grant execute on function public.is_my_session(uuid, text) to authenticated;

-- Profile: nur das eigene.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Athleten: Trainer alles, der verknüpfte Athlet liest seinen Eintrag.
drop policy if exists athletes_coach on public.athletes;
create policy athletes_coach on public.athletes for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());
drop policy if exists athletes_self on public.athletes;
create policy athletes_self on public.athletes for select to authenticated
  using (user_id = auth.uid());

-- Übungen: Trainer alles, verknüpfte Athleten lesen.
drop policy if exists exercises_coach on public.exercises;
create policy exercises_coach on public.exercises for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());
drop policy if exists exercises_athlete on public.exercises;
create policy exercises_athlete on public.exercises for select to authenticated
  using (public.is_athlete_of(coach_id));

-- Clips: nur der Trainer.
drop policy if exists clips_coach on public.clips;
create policy clips_coach on public.clips for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());

-- Einheiten: Trainer alles; der Athlet liest seine eigenen und darf sie
-- aktualisieren (der Trigger sessions_guard begrenzt das aufs Protokoll).
drop policy if exists sessions_coach on public.sessions;
create policy sessions_coach on public.sessions for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());
drop policy if exists sessions_athlete_select on public.sessions;
create policy sessions_athlete_select on public.sessions for select to authenticated
  using (public.is_my_session(coach_id, athlete_id));
drop policy if exists sessions_athlete_update on public.sessions;
create policy sessions_athlete_update on public.sessions for update to authenticated
  using (public.is_my_session(coach_id, athlete_id))
  with check (public.is_my_session(coach_id, athlete_id));

-- ---------------------------------------------------------------------------
-- Bilder: privater Bucket "media", Pfad <coach_id>/<bild_id>
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

drop policy if exists media_coach on storage.objects;
create policy media_coach on storage.objects for all to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

-- Wie is_athlete_of, aber mit dem Ordnernamen als Text (kein Cast, der bei
-- fremden Pfaden fehlschlagen könnte).
create or replace function public.is_athlete_of_folder(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athletes
    where coach_id::text = p_folder and user_id = auth.uid() and not deleted
  );
$$;

revoke all on function public.is_athlete_of_folder(text) from public, anon;
grant execute on function public.is_athlete_of_folder(text) to authenticated;

drop policy if exists media_athlete on storage.objects;
create policy media_athlete on storage.objects for select to authenticated
  using (
    bucket_id = 'media'
    and public.is_athlete_of_folder((storage.foldername(name))[1])
  );

-- PostgREST soll neue Tabellen/Funktionen sofort kennen.
notify pgrst, 'reload schema';
