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
