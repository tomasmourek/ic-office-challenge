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
