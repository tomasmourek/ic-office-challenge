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
