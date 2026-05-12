# Supabase setup — F1 až F22 (po merge do main)

Pokud jsi v minulosti spustil/a jen migrace `0001`–`0003`, tady je všechno, co
po merge celého stacku musíš ještě dotáhnout v Supabase.

## 1. SQL — jednorázový bundle

1. Otevři **Supabase Dashboard → SQL Editor → New query**.
2. Otevři raw view tohohle souboru a celý ho zkopíruj:
   <https://raw.githubusercontent.com/tomasmourek/ic-office-challenge/main/supabase/setup/RUN_THIS_BUNDLE.sql>
3. Vlep do SQL Editoru → **Run** (Ctrl+Enter).
4. Mělo by skončit zelenou hláškou „Success".

> Spouštět **jen jednou**. Druhé spuštění by selhalo na duplikovaných objektech
> (např. `create table`). Když selže s tím, že už něco existuje, znamená to, že
> bundle už proběhl.

Bundle obsahuje migrace 0004 až 0017:

- `0004` Realtime publikace pro výsledky + challenge
- `0005` meta jsonb sloupec do results (anti-cheat)
- `0006` Q&A schema (sessions, questions, votes)
- `0007` Q&A intro/outro fáze + video sloupce
- `0008` Tabulka attendees (registrace školení)
- `0009` Agenda + pauza countdown
- `0010` Materiály ke stažení
- `0011` Slidy embed URL
- `0012` Hudba na pozadí
- `0013` Slides zoom
- `0014` Reactions (emoji storm)
- `0015` Live polls (multiple choice / rating / word cloud)
- `0016` Feedback v outro
- `0017` Gamifikace Q&A

## 2. Storage buckety

V Supabase **Storage → New bucket**, vytvoř postupně **3 buckety**, vše
**Public bucket: ON**:

| Název | File size limit | Allowed MIME types |
|---|---|---|
| `session-materials` | 50 MB | (necháváš prázdné = všechny typy) |
| `session-audio`     | 30 MB | `audio/*,video/mp4` |
| `session-presentations` | 50 MB | `application/vnd.openxmlformats-officedocument.presentationml.presentation,application/vnd.ms-powerpoint,application/pdf` |

Pak v SQL Editoru spusť **bucket policies** (jeden blok pro všechny tři):

```sql
-- session-materials
create policy "session_materials_public_read"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'session-materials');

create policy "session_materials_admin_insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'session-materials');

create policy "session_materials_admin_delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'session-materials');

create policy "session_materials_admin_update"
  on storage.objects for update to authenticated
  using (bucket_id = 'session-materials')
  with check (bucket_id = 'session-materials');

-- session-audio
create policy "session_audio_public_read"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'session-audio');

create policy "session_audio_admin_insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'session-audio');

create policy "session_audio_admin_delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'session-audio');

create policy "session_audio_admin_update"
  on storage.objects for update to authenticated
  using (bucket_id = 'session-audio')
  with check (bucket_id = 'session-audio');

-- session-presentations
create policy "session_presentations_public_read"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'session-presentations');

create policy "session_presentations_admin_insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'session-presentations');

create policy "session_presentations_admin_delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'session-presentations');

create policy "session_presentations_admin_update"
  on storage.objects for update to authenticated
  using (bucket_id = 'session-presentations')
  with check (bucket_id = 'session-presentations');
```

## 3. Otestuj web

Po krocích 1 a 2 zkontroluj funkčnost:

| URL | Co by mělo fungovat |
|---|---|
| <https://www.ic-office-challenge.eu/> | Kvíz — projít registrací → 15 otázek → výsledek → tlačítka „Sdílet" / „📜 Stáhnout certifikát" / „Otevřít leaderboard ↗" |
| <https://www.ic-office-challenge.eu/leaderboard.html> | Veřejný leaderboard (QR widget v rohu, real-time) |
| <https://www.ic-office-challenge.eu/qa.html?admin=1> | Q&A admin login → e-mail `mourek@ic-office.eu` + heslo |
| <https://www.ic-office-challenge.eu/?challenge=test-brno> | Nová testovací soutěž (založ si přes admin) |

## 4. Co dělat když něco nefunguje

- **„Soutěž nenalezena"** v Q&A → není slug v DB. Otevři `/qa.html?admin=1`,
  klikni „+ Nová session" a vytvoř.
- **Otázky se nenačtou v kvízu** → migrace 0017 přidává `voter_token` do
  `qa_questions`, ale frontend ho čeká na všech ostatních dotazech. Spusť
  bundle SQL znovu nebo zkontroluj v Table Editoru, že sloupec existuje.
- **Foto upload selže** → Storage bucket nemá policies. Vrať se ke kroku 2.
- **Admin login po merge nefunguje s heslem `6371`** → správně. Od F2 je
  to Supabase Auth, e-mail `mourek@ic-office.eu` + heslo, které jsi
  nastavil v Add user (krok E1 v SUPABASE_SETUP.md).
