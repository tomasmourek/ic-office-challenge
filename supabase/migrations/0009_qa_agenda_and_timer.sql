-- Agenda dne školení + časomíra/pauza.
-- Lektor si nastaví rozvrh (např. „9:30-10:30 prezentace IC Office",
-- „10:30-10:45 pauza"). Účastníci i projektor uvidí harmonogram s vyznačeným
-- aktuálním blokem. Admin může spustit „Pauzu na 15 min" → public countdown.

-- =============================================================
-- 1. qa_agenda_items
-- =============================================================

create table public.qa_agenda_items (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references public.qa_sessions(id) on delete cascade,
  position     int not null,
  start_time   text not null,   -- 'HH:MM' v lokálním čase školení
  end_time     text not null,   -- 'HH:MM'
  title        text not null,
  description  text not null default '',
  kind         text not null default 'session'
                  check (kind in ('session','break','lunch','other')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (session_id, position)
);

create index qa_agenda_session_idx on public.qa_agenda_items (session_id, position);

create trigger qa_agenda_touch before update on public.qa_agenda_items
  for each row execute function public.touch_updated_at();

-- =============================================================
-- 2. RLS
-- =============================================================

alter table public.qa_agenda_items enable row level security;

-- Každý vidí agendu — slouží i pro projektor i pro účastníka.
create policy qa_agenda_select_all on public.qa_agenda_items
  for select using (true);

create policy qa_agenda_admin_write on public.qa_agenda_items
  for all to authenticated using (true) with check (true);

-- Realtime — když admin změní agendu, projektor se aktualizuje.
alter publication supabase_realtime add table public.qa_agenda_items;

-- =============================================================
-- 3. Časomíra/pauza — sloupce v qa_sessions
-- =============================================================

alter table public.qa_sessions
  add column if not exists break_until timestamptz,
  add column if not exists break_label text not null default 'Pauza končí za';

comment on column public.qa_sessions.break_until is
  'Když není NULL, zobrazí se na projektoru i účastnické stránce velký countdown do tohoto času. Lektor spouští přes admin tlačítka „Pauza 5/10/15/X min".';

comment on column public.qa_sessions.break_label is
  'Text před countdownem — defaultně „Pauza končí za", admin si může přepsat (např. „Oběd končí za").';
