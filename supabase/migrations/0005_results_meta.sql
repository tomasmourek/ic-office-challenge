-- Přidat `meta jsonb` sloupec do results pro anti-cheat audit data.
-- Frontend tam ukládá: user_agent, away_count, away_total_seconds, screen_size atd.
-- Admin v CSV uvidí, jestli někdo měl podezřele vysoký away_count.

alter table public.results
  add column if not exists meta jsonb not null default '{}'::jsonb;

-- Index na meta->>'away_count' pro rychlé queries v admin režimu
-- (např. „kdo měl víc než 5 přepnutí pryč").
create index if not exists results_meta_away_count_idx
  on public.results ((meta->>'away_count'));

comment on column public.results.meta is
  'Anti-cheat / diagnostická data. Klíče: user_agent, away_count (počet přepnutí pryč), '
  'away_total_seconds (sekundy strávené pryč), screen_width, screen_height, time_zone.';
