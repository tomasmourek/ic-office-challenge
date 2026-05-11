-- IC Office Challenge — počáteční schema
-- Spustit ve Supabase SQL Editoru jednou na čistém projektu.

-- =============================================================
-- 1. TABULKY
-- =============================================================

create table public.challenge (
  id                       uuid primary key default gen_random_uuid(),
  slug                     text unique not null,                 -- stabilní identifikátor pro URL, např. 'default'
  title                    text not null,                        -- veřejný název soutěže (admin může přejmenovat)
  intro_text               text not null default '',             -- popis akce pod titulkem
  question_count           int  not null default 15 check (question_count between 1 and 100),
  time_limit_minutes       int  not null default 15 check (time_limit_minutes between 1 and 180),
  show_rank_to_player      boolean not null default true,        -- vidí hráč svoje pořadí hned po dokončení?
  is_public_leaderboard    boolean not null default true,        -- smí anonymní návštěvník vidět leaderboard?
  display_mode             text not null default 'leaderboard'   -- co se ukazuje na public stránce
                            check (display_mode in ('leaderboard','youtube','closed')),
  youtube_video_id         text,                                 -- ID YouTube videa pro display_mode='youtube'
  active                   boolean not null default true,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create table public.questions (
  id           uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenge(id) on delete cascade,
  position     int  not null,                                    -- pořadí v rámci challenge
  text         text not null,
  options      jsonb not null,                                   -- pole stringů, např. ["a","b","c","d"]
  correct      text not null,                                    -- musí být jedna z hodnot v options
  image_path   text,                                             -- klíč v Storage bucketu 'question-images' (nullable)
  practical    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (challenge_id, position)
);

create index questions_challenge_pos_idx on public.questions (challenge_id, position);

create table public.results (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid not null references public.challenge(id) on delete cascade,
  name          text not null,
  phone         text,
  email         text,
  school        text,
  score         int  not null check (score >= 0),
  total         int  not null check (total >= 0),                -- z kolika otázek (snapshot v čase odeslání)
  time_seconds  int  not null check (time_seconds >= 0),
  finished_at   timestamptz not null default now()
);

create index results_challenge_rank_idx
  on public.results (challenge_id, score desc, time_seconds asc, finished_at asc);

-- =============================================================
-- 2. updated_at trigger
-- =============================================================

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger challenge_touch before update on public.challenge
  for each row execute function public.touch_updated_at();

create trigger questions_touch before update on public.questions
  for each row execute function public.touch_updated_at();

-- =============================================================
-- 3. Funkce pro veřejný leaderboard
--    Respektuje is_public_leaderboard toggle: anonymní zavolání
--    vrátí prázdno, pokud je leaderboard vypnutý. Authenticated
--    role (admin) vidí výsledky vždy.
-- =============================================================

create or replace function public.get_leaderboard(p_challenge_id uuid)
returns table (
  rank          bigint,
  name          text,
  school        text,
  score         int,
  total         int,
  time_seconds  int,
  finished_at   timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_public boolean;
  v_role text := current_setting('request.jwt.claims', true)::jsonb->>'role';
begin
  select is_public_leaderboard into v_is_public
    from public.challenge where id = p_challenge_id;

  if v_is_public is null then
    return;  -- challenge neexistuje
  end if;

  if v_is_public = false and coalesce(v_role,'anon') <> 'authenticated' then
    return;  -- public leaderboard vypnutý a volající není přihlášený admin
  end if;

  return query
  select
    row_number() over (order by r.score desc, r.time_seconds asc, r.finished_at asc) as rank,
    r.name, r.school, r.score, r.total, r.time_seconds, r.finished_at
  from public.results r
  where r.challenge_id = p_challenge_id
  order by r.score desc, r.time_seconds asc, r.finished_at asc;
end $$;

revoke all on function public.get_leaderboard(uuid) from public;
grant execute on function public.get_leaderboard(uuid) to anon, authenticated;

-- =============================================================
-- 4. Row Level Security
-- =============================================================

alter table public.challenge  enable row level security;
alter table public.questions  enable row level security;
alter table public.results    enable row level security;

-- challenge: každý smí SELECT aktivní soutěž; jen admin smí měnit
create policy challenge_select_active on public.challenge
  for select using (active = true or auth.role() = 'authenticated');

create policy challenge_admin_write on public.challenge
  for all to authenticated using (true) with check (true);

-- questions: každý smí SELECT (k zobrazení v kvízu); jen admin smí měnit
create policy questions_select_all on public.questions
  for select using (true);

create policy questions_admin_write on public.questions
  for all to authenticated using (true) with check (true);

-- results: každý smí INSERT (zápis vlastního výsledku),
--          SELECT/DELETE/UPDATE jen admin.
--          Veřejné čtení leaderboardu se dělá přes funkci get_leaderboard().
create policy results_insert_anon on public.results
  for insert to anon, authenticated with check (true);

create policy results_admin_read on public.results
  for select to authenticated using (true);

create policy results_admin_modify on public.results
  for update to authenticated using (true) with check (true);

create policy results_admin_delete on public.results
  for delete to authenticated using (true);

-- =============================================================
-- 5. Storage bucket pro obrázky otázek
--    (pouštět v Storage UI nebo přes SQL — viz SUPABASE_SETUP.md)
-- =============================================================
-- Záměrně NEvytvářím bucket v SQL — vytvoříš ho v Supabase Storage UI
-- (název: question-images, Public bucket: ON).
-- RLS policies pro bucket:
--   SELECT  → public  (každý smí stáhnout obrázek)
--   INSERT  → authenticated (jen admin smí nahrávat)
--   DELETE  → authenticated
-- Návod krok-po-kroku je v SUPABASE_SETUP.md.
