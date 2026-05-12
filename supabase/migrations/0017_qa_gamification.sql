-- F22 — Gamifikace Q&A. Body za interakci na školení; admin vidí top hráče.
--
-- Bodování:
--   dotaz (qa_questions)        + 5
--   hlas pro dotaz (qa_votes)   + 1
--   reakce (qa_reactions)       + 0.5  (zaokrouhleno na 1 v UI)
--   poll answer                 + 2
--   feedback v outro            + 5
--
-- Body se počítají on-the-fly z existujících tabulek — žádný materializovaný
-- countový sloupec, žádný cron job. Pro velkou session (>500 hráčů) by se
-- v budoucnu hodila view, ale pro typické školení (~50 hráčů) RPC postačí.

-- 1) Přidat voter_token do qa_questions, ať můžeme i otázky atribuovat hráči.
alter table public.qa_questions
  add column if not exists voter_token text;

create index if not exists qa_questions_voter_idx
  on public.qa_questions (voter_token)
  where voter_token is not null;

-- 2) RPC funkce — vrátí ranked seznam pro daný session_id.
--    Body se sčítají per voter_token; jméno se snažíme dohledat v attendees
--    (registrovaný účastník) nebo v qa_questions.author_name (nejnovější
--    podpis). Anonymní zůstávají s tokenem.
create or replace function public.get_qa_leaderboard(p_session_id uuid)
returns table (
  voter_token   text,
  display_name  text,
  question_pts  int,
  vote_pts      int,
  reaction_pts  int,
  poll_pts      int,
  feedback_pts  int,
  total_pts     int
)
language sql
security definer
set search_path = public
as $$
  with q as (
    select voter_token, count(*) as n
    from public.qa_questions
    where session_id = p_session_id and voter_token is not null
    group by voter_token
  ),
  v as (
    select v.voter_token, count(*) as n
    from public.qa_votes v
    join public.qa_questions q on q.id = v.question_id
    where q.session_id = p_session_id
    group by v.voter_token
  ),
  r as (
    select voter_token, count(*) as n
    from public.qa_reactions
    where session_id = p_session_id and voter_token is not null
    group by voter_token
  ),
  pa as (
    select a.voter_token, count(*) as n
    from public.qa_poll_answers a
    join public.qa_polls pp on pp.id = a.poll_id
    where pp.session_id = p_session_id
    group by a.voter_token
  ),
  f as (
    select voter_token, count(*) as n
    from public.qa_feedback
    where session_id = p_session_id
    group by voter_token
  ),
  tokens as (
    select voter_token from q   union
    select voter_token from v   union
    select voter_token from r   union
    select voter_token from pa  union
    select voter_token from f
  ),
  attendee_name as (
    select voter_token, max(company_or_name) as name
    from public.attendees
    where session_id = p_session_id and voter_token is not null
    group by voter_token
  ),
  question_name as (
    select voter_token, max(author_name) as name
    from public.qa_questions
    where session_id = p_session_id and voter_token is not null and author_name is not null
    group by voter_token
  )
  select
    t.voter_token,
    coalesce(an.name, qn.name, 'anonym ' || substring(t.voter_token, 1, 6)) as display_name,
    (coalesce(q.n, 0)  * 5)::int as question_pts,
    (coalesce(v.n, 0)  * 1)::int as vote_pts,
    -- 0.5 bodu × N reakcí, zaokrouhlit nahoru
    ceil(coalesce(r.n, 0) * 0.5)::int as reaction_pts,
    (coalesce(pa.n, 0) * 2)::int as poll_pts,
    (coalesce(f.n, 0)  * 5)::int as feedback_pts,
    (
      coalesce(q.n, 0)  * 5
      + coalesce(v.n, 0)  * 1
      + ceil(coalesce(r.n, 0) * 0.5)
      + coalesce(pa.n, 0) * 2
      + coalesce(f.n, 0)  * 5
    )::int as total_pts
  from tokens t
  left join q   on q.voter_token  = t.voter_token
  left join v   on v.voter_token  = t.voter_token
  left join r   on r.voter_token  = t.voter_token
  left join pa  on pa.voter_token = t.voter_token
  left join f   on f.voter_token  = t.voter_token
  left join attendee_name an on an.voter_token = t.voter_token
  left join question_name qn on qn.voter_token = t.voter_token
  where t.voter_token is not null
  order by total_pts desc, display_name asc;
$$;

revoke all on function public.get_qa_leaderboard(uuid) from public;
grant execute on function public.get_qa_leaderboard(uuid) to anon, authenticated;

comment on function public.get_qa_leaderboard(uuid) is
  'F22 — gamifikace Q&A. Vrací top hráče podle součtu bodů za otázky, '
  'hlasy, reakce, poll odpovědi a feedback. Anonymní hráči se zobrazí '
  'jako „anonym <6-znakový prefix tokenu>".';
