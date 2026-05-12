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
