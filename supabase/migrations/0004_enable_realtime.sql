-- Povolit Supabase Realtime na tabulkách potřebných pro veřejný leaderboard.
-- Realtime běží jen na tabulkách přidaných do publication `supabase_realtime`.
--
-- Spustit ve Supabase SQL Editoru po předchozích migracích.

-- Veřejný leaderboard subscribe-uje INSERT/DELETE na results,
-- aby se nový výsledek hned objevil + konfetti efekt.
alter publication supabase_realtime add table public.results;

-- UPDATE na challenge spouští re-aplikaci display_mode (leaderboard/youtube/closed)
-- a změny youtube_video_id / is_public_leaderboard u běžícího projektoru.
alter publication supabase_realtime add table public.challenge;

-- Pozn: questions tabulka v realtime být nemusí — admin si po úpravě otázek
-- ručně refreshne. Otázky nejsou zobrazované na leaderboardu.
