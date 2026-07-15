# IC Office Challenge

Statická webová **kvízová soutěž** o systému IC Office — pro studenty, mechaniky a mistry.
Živě na **[www.ic-office-challenge.eu](https://www.ic-office-challenge.eu)** (GitHub Pages).

## Části

| Stránka | Co dělá |
|---------|---------|
| `index.html` | kvíz (otázky, vyhodnocení, PDF certifikát) |
| `qa.html` | živý Q&A / prezentační modul |
| `leaderboard.html` | veřejný žebříček |

PWA (`sw.js` + `site.webmanifest`), bez build systému — čisté HTML/CSS/vanilla JS.

## Backend

**Supabase** (Postgres + Storage + RLS). Nastavení: [`SUPABASE_SETUP.md`](SUPABASE_SETUP.md),
migrace v [`supabase/migrations/`](supabase/migrations/).

Klient používá **publishable/anon klíč** (veřejný z principu). Data chrání **RLS**:
anonym smí číst otázky a aktivní challenge, vložit vlastní výsledek a číst žebříček přes
kontrolovanou funkci; čtení/zápis výsledků a správa jsou admin-only.

## Nasazení

GitHub Pages z větve `main` (root), custom doména přes `CNAME`.

## Licence

Proprietární — viz [LICENSE](LICENSE). Není open-source.
