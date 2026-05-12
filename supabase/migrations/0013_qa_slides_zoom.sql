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
