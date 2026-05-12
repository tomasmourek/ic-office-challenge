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
