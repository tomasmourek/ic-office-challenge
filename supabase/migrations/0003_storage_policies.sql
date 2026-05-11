-- Storage policies pro bucket 'question-images'.
-- Bucket musí už existovat (vytvořený v Storage UI s Public bucket = ON).
-- Spustit v SQL Editoru po vytvoření bucketu.

-- 1) Veřejné čtení — každý (anon i přihlášený admin) si smí stáhnout obrázek.
--    Public bucket toggle už by to umožňoval, ale explicitní policy je
--    deterministická a nezávisí na zapnutém toggle.
create policy "question_images_public_read"
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'question-images');

-- 2) Nahrávání jen pro přihlášeného admina (Supabase Auth user).
create policy "question_images_admin_insert"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'question-images');

-- 3) Mazání jen pro přihlášeného admina.
create policy "question_images_admin_delete"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'question-images');

-- 4) Update (přepsání souboru) jen pro admina — užitečné při výměně fotky.
create policy "question_images_admin_update"
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'question-images')
  with check (bucket_id = 'question-images');
