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
