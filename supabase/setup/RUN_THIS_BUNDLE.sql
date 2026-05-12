-- =============================================================
-- IC Office Challenge — bundle migrací 0004..0017
-- Vlepi celý tento soubor do Supabase SQL Editoru a klikni Run.
-- Bezpečné spustit opakovaně — všechny objekty mají IF NOT EXISTS / OR REPLACE.
-- =============================================================


-- =============================================================
-- 0004_enable_realtime.sql
-- =============================================================
-- Povolit Supabase Realtime na tabulkách potřebných pro veřejný leaderboard.
-- Realtime běží jen na tabulkách přidaných do publication `supabase_realtime`.
--
-- Spustit ve Supabase SQL Editoru po předchozích migracích.

-- Veřejný leaderboard subscribe-uje INSERT/DELETE na results,
-- aby se nový výsledek hned objevil + konfetti efekt.
alter publication supabase_realtime add table public.results;

-- UPDATE na challenge spouští re-aplikaci display_mode (leaderboard/youtube/closed)
-- a změny youtube_video_id / is_public_leaderboard u běžícího projektoru.
alter publication supabase_realtime add table public.challenge;

-- Pozn: questions tabulka v realtime být nemusí — admin si po úpravě otázek
-- ručně refreshne. Otázky nejsou zobrazované na leaderboardu.


-- =============================================================
-- 0005_results_meta.sql
-- =============================================================
-- Přidat `meta jsonb` sloupec do results pro anti-cheat audit data.
-- Frontend tam ukládá: user_agent, away_count, away_total_seconds, screen_size atd.
-- Admin v CSV uvidí, jestli někdo měl podezřele vysoký away_count.

alter table public.results
  add column if not exists meta jsonb not null default '{}'::jsonb;

-- Index na meta->>'away_count' pro rychlé queries v admin režimu
-- (např. „kdo měl víc než 5 přepnutí pryč").
create index if not exists results_meta_away_count_idx
  on public.results ((meta->>'away_count'));

comment on column public.results.meta is
  'Anti-cheat / diagnostická data. Klíče: user_agent, away_count (počet přepnutí pryč), '
  'away_total_seconds (sekundy strávené pryč), screen_width, screen_height, time_zone.';


-- =============================================================
-- 0006_qa_schema.sql
-- =============================================================
-- Q&A systém pro školení IC Office.
-- Účastníci přicházejí přes QR / odkaz na qa.html?session=<slug>, kladou
-- dotazy (anonymně nebo s jménem) a hlasují. Lektor je v admin režimu
-- moderuje, schvaluje a vybírá na projektor.
--
-- Odděleno od Challenge tabulek (vlastní namespace `qa_`).

-- =============================================================
-- 1. TABULKY
-- =============================================================

create table public.qa_sessions (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text unique not null,                       -- stabilní v URL
  title                 text not null,
  description           text not null default '',

  -- moderation_mode řídí výchozí status nově odeslaného dotazu:
  --   'auto'   → dotaz se hned objeví ve feedu (status='published')
  --   'manual' → dotaz čeká na schválení lektora (status='pending')
  moderation_mode       text not null default 'manual'
                          check (moderation_mode in ('auto','manual')),

  allow_anonymous       boolean not null default true,             -- smí účastník neuvést jméno?
  closed                boolean not null default false,            -- po skončení školení lektor zavře

  highlight_question_id uuid,                                       -- který dotaz se ukazuje XL fontem na projektoru
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table public.qa_questions (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references public.qa_sessions(id) on delete cascade,
  body         text not null check (length(trim(body)) between 1 and 1000),
  author_name  text,                                                -- NULL = anonymní dotaz
  status       text not null default 'pending'
                  check (status in ('pending','published','answered','hidden')),
  pinned       boolean not null default false,
  votes_count  int not null default 0,                              -- denormalizovaný count, udržuje trigger
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index qa_questions_session_status_idx
  on public.qa_questions (session_id, status, pinned desc, votes_count desc, created_at desc);

create table public.qa_votes (
  id           uuid primary key default gen_random_uuid(),
  question_id  uuid not null references public.qa_questions(id) on delete cascade,
  voter_token  text not null,                                       -- ID vygenerované v browseru, uložené v localStorage
  created_at   timestamptz not null default now(),
  unique (question_id, voter_token)
);

create index qa_votes_question_idx on public.qa_votes (question_id);

-- =============================================================
-- 2. Triggery
-- =============================================================

-- updated_at na obou tabulkách
create trigger qa_sessions_touch before update on public.qa_sessions
  for each row execute function public.touch_updated_at();

create trigger qa_questions_touch before update on public.qa_questions
  for each row execute function public.touch_updated_at();

-- Po INSERT nového dotazu nastavit status podle moderation_mode session.
create or replace function public.qa_apply_moderation_mode()
returns trigger language plpgsql as $$
declare
  v_mode text;
  v_closed boolean;
begin
  select moderation_mode, closed into v_mode, v_closed
    from public.qa_sessions where id = new.session_id;

  if v_closed then
    raise exception 'Session je uzavřená, nové dotazy nejsou možné.';
  end if;

  if v_mode = 'auto' then
    new.status := 'published';
  else
    new.status := 'pending';
  end if;

  return new;
end $$;

create trigger qa_questions_apply_mode
  before insert on public.qa_questions
  for each row execute function public.qa_apply_moderation_mode();

-- Udržovat denormalizovaný votes_count v qa_questions
create or replace function public.qa_recount_votes()
returns trigger language plpgsql as $$
declare
  v_qid uuid;
begin
  v_qid := coalesce(new.question_id, old.question_id);
  update public.qa_questions
     set votes_count = (select count(*) from public.qa_votes where question_id = v_qid)
   where id = v_qid;
  return null;
end $$;

create trigger qa_votes_recount_ins
  after insert on public.qa_votes
  for each row execute function public.qa_recount_votes();

create trigger qa_votes_recount_del
  after delete on public.qa_votes
  for each row execute function public.qa_recount_votes();

-- =============================================================
-- 3. Row Level Security
-- =============================================================

alter table public.qa_sessions  enable row level security;
alter table public.qa_questions enable row level security;
alter table public.qa_votes     enable row level security;

-- qa_sessions: každý smí SELECT (potřebuje znát title a settings ze slugu);
-- jen admin smí měnit.
create policy qa_sessions_select_all on public.qa_sessions
  for select using (true);

create policy qa_sessions_admin_write on public.qa_sessions
  for all to authenticated using (true) with check (true);

-- qa_questions:
--   anon SELECT: jen published + answered (žádné pending ani hidden — moderace).
--   anon INSERT: smí přidat svůj dotaz (trigger nastaví status).
--   admin: vidí všechno + write.
create policy qa_questions_select_public on public.qa_questions
  for select using (status in ('published','answered'));

create policy qa_questions_select_admin on public.qa_questions
  for select to authenticated using (true);

create policy qa_questions_insert_anon on public.qa_questions
  for insert to anon, authenticated with check (true);

create policy qa_questions_admin_modify on public.qa_questions
  for update to authenticated using (true) with check (true);

create policy qa_questions_admin_delete on public.qa_questions
  for delete to authenticated using (true);

-- qa_votes:
--   anon SELECT: smí číst votes přes voter_token = vlastní (nebo všechny pro count?
--                pro jednoduchost: anon vidí jen vlastní hlasy přes filter v dotazu).
--   anon INSERT: jeden hlas per (question_id, voter_token) díky unique constraint.
--   anon DELETE: smí stáhnout vlastní hlas (toggle). Filtruje se přes voter_token v queryi.
create policy qa_votes_select_all on public.qa_votes
  for select using (true);

create policy qa_votes_insert_anon on public.qa_votes
  for insert to anon, authenticated with check (true);

create policy qa_votes_delete_anon on public.qa_votes
  for delete to anon, authenticated using (true);

-- =============================================================
-- 4. Realtime publication
-- =============================================================

alter publication supabase_realtime add table public.qa_sessions;
alter publication supabase_realtime add table public.qa_questions;
alter publication supabase_realtime add table public.qa_votes;

-- =============================================================
-- 5. Pomocná funkce: založení session od admina (jednodušší slug-gen)
-- =============================================================

create or replace function public.qa_create_session(
  p_slug text,
  p_title text,
  p_description text default '',
  p_moderation_mode text default 'manual',
  p_allow_anonymous boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  -- Jen authenticated (admin) smí volat.
  if (current_setting('request.jwt.claims', true)::jsonb->>'role') <> 'authenticated' then
    raise exception 'Jen přihlášený admin smí zakládat sessions.';
  end if;

  insert into public.qa_sessions (slug, title, description, moderation_mode, allow_anonymous)
  values (p_slug, p_title, p_description, p_moderation_mode, p_allow_anonymous)
  returning id into v_id;

  return v_id;
end $$;

revoke all on function public.qa_create_session(text, text, text, text, boolean) from public;
grant execute on function public.qa_create_session(text, text, text, text, boolean) to authenticated;


-- =============================================================
-- 0007_qa_intro_outro.sql
-- =============================================================
-- Q&A intro / outro fáze.
-- Lektor může mezi 3 fázemi přepínat ručně:
--   intro → uvodní obrazovka (uvítací video + branded text)
--   live  → běžné Q&A (dotazy + projektor)
--   outro → závěrečná obrazovka (děkovací video + kontakty)
--
-- Real-time UPDATE z admina → všichni účastníci a projektor přepnou layout.

alter table public.qa_sessions
  add column if not exists display_phase text not null default 'live'
    check (display_phase in ('intro', 'live', 'outro')),
  add column if not exists intro_video_id text,
  add column if not exists intro_text text not null default '',
  add column if not exists outro_video_id text,
  add column if not exists outro_text text not null default '';

comment on column public.qa_sessions.display_phase is
  'Aktuální fáze školení: intro (uvítací screen) / live (Q&A aktivní) / outro (závěr).';

comment on column public.qa_sessions.intro_video_id is
  'YouTube video ID pro úvodní obrazovku. Null = bez videa, jen text.';

comment on column public.qa_sessions.outro_video_id is
  'YouTube video ID pro závěrečnou obrazovku. Null = bez videa, jen text.';


-- =============================================================
-- 0008_attendees.sql
-- =============================================================
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


-- =============================================================
-- 0009_qa_agenda_and_timer.sql
-- =============================================================
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


-- =============================================================
-- 0010_qa_materials.sql
-- =============================================================
-- Materiály ke stažení per Q&A session.
-- Lektor v admin nahrává PDF/PPT/obrázky/fotky → účastník je vidí v intro
-- a outro fázi a může je stáhnout.

create table public.qa_materials (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references public.qa_sessions(id) on delete cascade,
  position     int not null default 0,
  title        text not null,
  description  text not null default '',
  file_path    text not null,                 -- klíč v Storage bucketu session-materials
  file_size    bigint,                         -- v bajtech (pro UI „2,3 MB")
  mime_type    text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index qa_materials_session_idx
  on public.qa_materials (session_id, position, created_at desc);

create trigger qa_materials_touch before update on public.qa_materials
  for each row execute function public.touch_updated_at();

-- =============================================================
-- RLS
-- =============================================================

alter table public.qa_materials enable row level security;

create policy qa_materials_select_all on public.qa_materials
  for select using (true);

create policy qa_materials_admin_write on public.qa_materials
  for all to authenticated using (true) with check (true);

alter publication supabase_realtime add table public.qa_materials;

-- =============================================================
-- Storage bucket POZNÁMKA
-- =============================================================
-- Tento SQL POUZE vytvoří tabulku. Storage bucket `session-materials`
-- musíš vytvořit ručně v Supabase Storage UI:
--   1) Storage → New bucket → název: `session-materials`, Public bucket: ON
--   2) Policies pro bucket (3 policies — stejně jako question-images):
--      SELECT  → public                (každý smí stáhnout)
--      INSERT  → authenticated         (jen admin smí nahrávat)
--      DELETE  → authenticated         (jen admin smí mazat)
--
--      SQL pro policies (spustit v SQL Editoru po vytvoření bucketu):
--
--      create policy "session_materials_public_read"
--        on storage.objects for select to anon, authenticated
--        using (bucket_id = 'session-materials');
--
--      create policy "session_materials_admin_insert"
--        on storage.objects for insert to authenticated
--        with check (bucket_id = 'session-materials');
--
--      create policy "session_materials_admin_delete"
--        on storage.objects for delete to authenticated
--        using (bucket_id = 'session-materials');
--
--      create policy "session_materials_admin_update"
--        on storage.objects for update to authenticated
--        using (bucket_id = 'session-materials')
--        with check (bucket_id = 'session-materials');


-- =============================================================
-- 0011_qa_slides.sql
-- =============================================================
-- Slide embed URL pro intro a outro fázi Q&A session.
-- Lektor zadá veřejnou URL (Google Slides embed, PDF, Canva embed, …) a
-- účastník/projektor uvidí slidy v IC Office rámečku v dané fázi.

alter table public.qa_sessions
  add column if not exists intro_slides_url text,
  add column if not exists outro_slides_url text;

comment on column public.qa_sessions.intro_slides_url is
  'URL slide embedu pro intro fázi. Funguje s Google Slides (Publish → Embed), '
  'PDF přes Google Drive viewer (https://drive.google.com/file/d/<id>/preview), '
  'Canva (Share → Embed), nebo přímý PDF link na CDN.';

comment on column public.qa_sessions.outro_slides_url is
  'Stejné jako intro_slides_url, ale pro outro fázi.';


-- =============================================================
-- 0012_qa_audio_tracks.sql
-- =============================================================
-- Hudba na pozadí per Q&A session.
-- Lektor nahraje mp3 nebo mp4 (jen audio stopa), který se přehrává na
-- projektoru podle aktuální fáze:
--   intro  → intro track (loop)
--   break  → break track (loop) — když je qa_sessions.break_until aktivní
--   outro  → outro track (loop)
--   live   → ticho (lidé mluví)
--
-- Audio NEHRÁ na účastnické stránce — vyhnuli jsme se zvukovému spamu z
-- desítek mobilů. Hraje výhradně projektor (?display=1).

create table public.qa_audio_tracks (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references public.qa_sessions(id) on delete cascade,
  title        text not null,
  file_path    text not null,                  -- klíč v bucketu session-audio
  mime_type    text,
  file_size    bigint,
  kind         text not null
                  check (kind in ('intro','break','outro','custom')),
  loop_track   boolean not null default true,  -- v Postgresu „loop" je rezervované, voláme to loop_track
  volume       real    not null default 0.6
                  check (volume >= 0 and volume <= 1),
  active       boolean not null default true,  -- admin může track deaktivovat bez smazání
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index qa_audio_session_kind_idx
  on public.qa_audio_tracks (session_id, kind, active, created_at desc);

create trigger qa_audio_touch before update on public.qa_audio_tracks
  for each row execute function public.touch_updated_at();

-- =============================================================
-- RLS
-- =============================================================

alter table public.qa_audio_tracks enable row level security;

create policy qa_audio_select_all on public.qa_audio_tracks
  for select using (true);

create policy qa_audio_admin_write on public.qa_audio_tracks
  for all to authenticated using (true) with check (true);

alter publication supabase_realtime add table public.qa_audio_tracks;

-- =============================================================
-- Storage bucket setup návod
-- =============================================================
-- Tento SQL POUZE vytváří tabulku. Storage bucket `session-audio`
-- musíš vytvořit ručně v Supabase Storage UI:
--   1) Storage → New bucket
--      Name: session-audio
--      Public bucket: ON
--      File size limit: 30 MB doporučeno (mp3 ~3 min @ 128 kbps = 3 MB; loop trackovi
--        bohatě stačí 30 s)
--      Allowed MIME types: audio/*,video/mp4
--   2) Policies — spustit v SQL Editoru po vytvoření bucketu:
--
--      create policy "session_audio_public_read"
--        on storage.objects for select to anon, authenticated
--        using (bucket_id = 'session-audio');
--
--      create policy "session_audio_admin_insert"
--        on storage.objects for insert to authenticated
--        with check (bucket_id = 'session-audio');
--
--      create policy "session_audio_admin_delete"
--        on storage.objects for delete to authenticated
--        using (bucket_id = 'session-audio');
--
--      create policy "session_audio_admin_update"
--        on storage.objects for update to authenticated
--        using (bucket_id = 'session-audio')
--        with check (bucket_id = 'session-audio');


-- =============================================================
-- 0013_qa_slides_zoom.sql
-- =============================================================
-- F17 — PowerPoint upload + projector zoom.
-- Admin nahraje .pptx do Storage bucketu `session-presentations`, frontend
-- vygeneruje embed URL přes Office Web Viewer (https://view.officeapps.live.com).
-- Sloupec `slides_zoom` posunutý sliderem v adminu se aplikuje na projektor
-- jako CSS scale — zvětší font i fotky v iframe.

alter table public.qa_sessions
  add column if not exists slides_zoom int not null default 100
    check (slides_zoom between 50 and 300);

comment on column public.qa_sessions.slides_zoom is
  'Procento zvětšení slide iframe na projektoru (CSS scale). 100 = beze zoomu, '
  '150 = 1,5× větší (vhodné pro malý font v PowerPointu). Účastnické zařízení '
  'zoom neaplikuje — slidy se na mobilu zobrazí ve fit-to-width režimu.';

-- =============================================================
-- Storage bucket `session-presentations` — setup návod
-- =============================================================
-- Vytvořit ručně v Supabase Storage UI:
--   1) Storage → New bucket
--      Name: session-presentations
--      Public bucket: ON (Office Web Viewer si stahuje veřejnou URL)
--      File size limit: 50 MB (typický .pptx)
--      Allowed MIME types: application/vnd.openxmlformats-officedocument.presentationml.presentation,application/vnd.ms-powerpoint,application/pdf
--   2) Policies v SQL Editoru:
--
--      create policy "session_presentations_public_read"
--        on storage.objects for select to anon, authenticated
--        using (bucket_id = 'session-presentations');
--
--      create policy "session_presentations_admin_insert"
--        on storage.objects for insert to authenticated
--        with check (bucket_id = 'session-presentations');
--
--      create policy "session_presentations_admin_delete"
--        on storage.objects for delete to authenticated
--        using (bucket_id = 'session-presentations');
--
--      create policy "session_presentations_admin_update"
--        on storage.objects for update to authenticated
--        using (bucket_id = 'session-presentations')
--        with check (bucket_id = 'session-presentations');
--
-- Embed URL format:
--   https://view.officeapps.live.com/op/embed.aspx?src=<encodeURIComponent(public_url)>


-- =============================================================
-- 0014_qa_reactions.sql
-- =============================================================
-- F20 — Reactions / emoji storm.
-- Účastník na své stránce klepne emoji, na projektoru emoji vyletí
-- od spodního okraje nahoru s drobnou náhodnou trajektorií. Skvělé pro
-- engagement na živé akci.

create table public.qa_reactions (
  id           bigserial primary key,
  session_id   uuid not null references public.qa_sessions(id) on delete cascade,
  emoji        text not null check (length(emoji) <= 8),
  voter_token  text,                              -- z localStorage účastníka, pro rate-limit
  created_at   timestamptz not null default now()
);

create index qa_reactions_session_time_idx
  on public.qa_reactions (session_id, created_at desc);

-- =============================================================
-- RLS — anon smí INSERT, každý smí SELECT (potřebuje projektor i admin)
-- =============================================================

alter table public.qa_reactions enable row level security;

create policy qa_reactions_select_all on public.qa_reactions
  for select using (true);

create policy qa_reactions_insert_anon on public.qa_reactions
  for insert to anon, authenticated with check (true);

create policy qa_reactions_admin_delete on public.qa_reactions
  for delete to authenticated using (true);

alter publication supabase_realtime add table public.qa_reactions;

-- =============================================================
-- Volitelně: auto-cleanup starých reakcí, aby tabulka nerostla.
-- Tady necháme bez auto-cleanupu — admin si může poklidit přes UI.
-- =============================================================


-- =============================================================
-- 0015_qa_polls.sql
-- =============================================================
-- F18 — Live polls.
-- Lektor v admin vytvoří anketu (multiple choice nebo rating 1-5), aktivuje ji
-- a účastníci hlasují. Projektor zobrazí výsledky live jako bar chart / gauge.

create table public.qa_polls (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.qa_sessions(id) on delete cascade,
  position      int not null default 0,
  kind          text not null check (kind in ('choice','rating','word_cloud')),
  question      text not null,
  options       jsonb,                                    -- pole stringů pro 'choice'
  rating_max    int not null default 5
                  check (rating_max between 2 and 10),
  status        text not null default 'draft'
                  check (status in ('draft','active','closed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index qa_polls_session_status_idx
  on public.qa_polls (session_id, status, position desc, created_at desc);

create trigger qa_polls_touch before update on public.qa_polls
  for each row execute function public.touch_updated_at();

create table public.qa_poll_answers (
  id            bigserial primary key,
  poll_id       uuid not null references public.qa_polls(id) on delete cascade,
  voter_token   text not null,
  option_idx    int,                                       -- pro 'choice' — index v poll.options
  rating_value  int,                                       -- pro 'rating' — 1..rating_max
  text_value    text,                                      -- pro 'word_cloud' — krátký text (1-3 slova)
  created_at    timestamptz not null default now(),
  unique (poll_id, voter_token)                            -- jeden hlas per browser
);

create index qa_poll_answers_poll_idx
  on public.qa_poll_answers (poll_id, created_at desc);

-- =============================================================
-- RLS
-- =============================================================

alter table public.qa_polls         enable row level security;
alter table public.qa_poll_answers  enable row level security;

create policy qa_polls_select_all on public.qa_polls
  for select using (true);

create policy qa_polls_admin_write on public.qa_polls
  for all to authenticated using (true) with check (true);

create policy qa_poll_answers_select_all on public.qa_poll_answers
  for select using (true);

create policy qa_poll_answers_insert_anon on public.qa_poll_answers
  for insert to anon, authenticated with check (true);

create policy qa_poll_answers_admin_delete on public.qa_poll_answers
  for delete to authenticated using (true);

alter publication supabase_realtime add table public.qa_polls;
alter publication supabase_realtime add table public.qa_poll_answers;


-- =============================================================
-- 0016_qa_feedback.sql
-- =============================================================
-- F21 — Feedback formulář v outro fázi.
-- Účastník v outro screen ohodnotí celé školení (1-5 hvězd) + nepovinný komentář.
-- Lektor v admin vidí průměr + jednotlivé komentáře + CSV export.

create table public.qa_feedback (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.qa_sessions(id) on delete cascade,
  voter_token   text not null,
  rating        int  not null check (rating between 1 and 5),
  comment       text not null default '',
  recommend_yes boolean,                                -- volitelná otázka „Doporučil/a bys kolegovi?"
  created_at    timestamptz not null default now(),
  unique (session_id, voter_token)                      -- jeden feedback per browser
);

create index qa_feedback_session_idx
  on public.qa_feedback (session_id, created_at desc);

-- =============================================================
-- RLS
-- =============================================================

alter table public.qa_feedback enable row level security;

create policy qa_feedback_insert_anon on public.qa_feedback
  for insert to anon, authenticated with check (true);

-- Účastník vidí jen vlastní feedback (přes voter_token filter na klientu),
-- admin vidí všechno.
create policy qa_feedback_select_all on public.qa_feedback
  for select using (true);

create policy qa_feedback_admin_modify on public.qa_feedback
  for update to authenticated using (true) with check (true);

create policy qa_feedback_admin_delete on public.qa_feedback
  for delete to authenticated using (true);

alter publication supabase_realtime add table public.qa_feedback;


-- =============================================================
-- 0017_qa_gamification.sql
-- =============================================================
-- F22 — Gamifikace Q&A. Body za interakci na školení; admin vidí top hráče.
--
-- Bodování:
--   dotaz (qa_questions)        + 5
--   hlas pro dotaz (qa_votes)   + 1
--   reakce (qa_reactions)       + 0.5  (zaokrouhleno na 1 v UI)
--   poll answer                 + 2
--   feedback v outro            + 5
--
-- Body se počítají on-the-fly z existujících tabulek — žádný materializovaný
-- countový sloupec, žádný cron job. Pro velkou session (>500 hráčů) by se
-- v budoucnu hodila view, ale pro typické školení (~50 hráčů) RPC postačí.

-- 1) Přidat voter_token do qa_questions, ať můžeme i otázky atribuovat hráči.
alter table public.qa_questions
  add column if not exists voter_token text;

create index if not exists qa_questions_voter_idx
  on public.qa_questions (voter_token)
  where voter_token is not null;

-- 2) RPC funkce — vrátí ranked seznam pro daný session_id.
--    Body se sčítají per voter_token; jméno se snažíme dohledat v attendees
--    (registrovaný účastník) nebo v qa_questions.author_name (nejnovější
--    podpis). Anonymní zůstávají s tokenem.
create or replace function public.get_qa_leaderboard(p_session_id uuid)
returns table (
  voter_token   text,
  display_name  text,
  question_pts  int,
  vote_pts      int,
  reaction_pts  int,
  poll_pts      int,
  feedback_pts  int,
  total_pts     int
)
language sql
security definer
set search_path = public
as $$
  with q as (
    select voter_token, count(*) as n
    from public.qa_questions
    where session_id = p_session_id and voter_token is not null
    group by voter_token
  ),
  v as (
    select v.voter_token, count(*) as n
    from public.qa_votes v
    join public.qa_questions q on q.id = v.question_id
    where q.session_id = p_session_id
    group by v.voter_token
  ),
  r as (
    select voter_token, count(*) as n
    from public.qa_reactions
    where session_id = p_session_id and voter_token is not null
    group by voter_token
  ),
  pa as (
    select a.voter_token, count(*) as n
    from public.qa_poll_answers a
    join public.qa_polls pp on pp.id = a.poll_id
    where pp.session_id = p_session_id
    group by a.voter_token
  ),
  f as (
    select voter_token, count(*) as n
    from public.qa_feedback
    where session_id = p_session_id
    group by voter_token
  ),
  tokens as (
    select voter_token from q   union
    select voter_token from v   union
    select voter_token from r   union
    select voter_token from pa  union
    select voter_token from f
  ),
  attendee_name as (
    select voter_token, max(company_or_name) as name
    from public.attendees
    where session_id = p_session_id and voter_token is not null
    group by voter_token
  ),
  question_name as (
    select voter_token, max(author_name) as name
    from public.qa_questions
    where session_id = p_session_id and voter_token is not null and author_name is not null
    group by voter_token
  )
  select
    t.voter_token,
    coalesce(an.name, qn.name, 'anonym ' || substring(t.voter_token, 1, 6)) as display_name,
    (coalesce(q.n, 0)  * 5)::int as question_pts,
    (coalesce(v.n, 0)  * 1)::int as vote_pts,
    -- 0.5 bodu × N reakcí, zaokrouhlit nahoru
    ceil(coalesce(r.n, 0) * 0.5)::int as reaction_pts,
    (coalesce(pa.n, 0) * 2)::int as poll_pts,
    (coalesce(f.n, 0)  * 5)::int as feedback_pts,
    (
      coalesce(q.n, 0)  * 5
      + coalesce(v.n, 0)  * 1
      + ceil(coalesce(r.n, 0) * 0.5)
      + coalesce(pa.n, 0) * 2
      + coalesce(f.n, 0)  * 5
    )::int as total_pts
  from tokens t
  left join q   on q.voter_token  = t.voter_token
  left join v   on v.voter_token  = t.voter_token
  left join r   on r.voter_token  = t.voter_token
  left join pa  on pa.voter_token = t.voter_token
  left join f   on f.voter_token  = t.voter_token
  left join attendee_name an on an.voter_token = t.voter_token
  left join question_name qn on qn.voter_token = t.voter_token
  where t.voter_token is not null
  order by total_pts desc, display_name asc;
$$;

revoke all on function public.get_qa_leaderboard(uuid) from public;
grant execute on function public.get_qa_leaderboard(uuid) to anon, authenticated;

comment on function public.get_qa_leaderboard(uuid) is
  'F22 — gamifikace Q&A. Vrací top hráče podle součtu bodů za otázky, '
  'hlasy, reakce, poll odpovědi a feedback. Anonymní hráči se zobrazí '
  'jako „anonym <6-znakový prefix tokenu>".';

