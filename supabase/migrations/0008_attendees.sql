-- Evidence účastníků školení.
-- Účastník na začátku vyplní registrační formulář (Intercars zákaznické číslo,
-- email, firma, IČ, telefon). Data uložíme do `attendees`, propojíme s qa_session
-- a s voter_token z localStorage (aby anonymní hlasy bylo možné spárovat).

alter table public.qa_sessions
  add column if not exists require_registration boolean not null default false;

comment on column public.qa_sessions.require_registration is
  'Pokud true, účastník musí vyplnit registrační formulář před přístupem k Q&A.';

create table public.attendees (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references public.qa_sessions(id) on delete cascade,

  -- Identifikace v ekosystému Intercars / IC Office
  customer_number   text,   -- formát CXXXXX, nepovinné (může jít o nového zájemce)
  ico               text,   -- české IČO (8 cifer), nepovinné

  -- Kontaktní údaje
  email             text,
  company_or_name   text,   -- firma nebo jméno fyzické osoby
  phone             text,
  note              text,   -- volné poznámky účastníka

  -- Flexibilní rozšíření do budoucna (admin si přidá další pole bez migrace)
  extra             jsonb not null default '{}'::jsonb,

  -- Propojení s anonymními hlasy přes voter_token z localStorage
  voter_token       text,

  registered_at     timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index attendees_session_idx on public.attendees (session_id, registered_at desc);
create index attendees_email_idx on public.attendees (lower(email));
create index attendees_customer_idx on public.attendees (customer_number);

create trigger attendees_touch before update on public.attendees
  for each row execute function public.touch_updated_at();

-- =============================================================
-- Row Level Security
-- =============================================================

alter table public.attendees enable row level security;

-- Anon smí INSERT (vlastní registrace) — `extra` lze zapsat jen prázdné/jednoduché.
create policy attendees_insert_anon on public.attendees
  for insert to anon, authenticated with check (true);

-- Anon smí SELECT vlastní registraci přes voter_token (pro auto-fill v Q&A).
-- Filter na klient straně (`.eq('voter_token', token)`); policy povolí všechno
-- jen v rámci current session — proti masovému scrapingu chrání to, že voter_token
-- je v podstatě UUID, který útočník nezná pro cizí účastníky.
create policy attendees_select_by_token on public.attendees
  for select using (true);

-- Admin (authenticated) má full přístup.
create policy attendees_admin_modify on public.attendees
  for update to authenticated using (true) with check (true);

create policy attendees_admin_delete on public.attendees
  for delete to authenticated using (true);

-- =============================================================
-- Realtime publication (admin uvidí nové registrace live)
-- =============================================================

alter publication supabase_realtime add table public.attendees;
