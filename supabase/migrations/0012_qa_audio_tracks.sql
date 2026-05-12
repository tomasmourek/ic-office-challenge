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
