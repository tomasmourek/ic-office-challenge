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
