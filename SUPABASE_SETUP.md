# Supabase setup — IC Office Challenge

Tento návod tě provede založením Supabase projektu, který bude sloužit jako trvalá databáze a úložiště fotek pro IC Office Challenge.

> Cíl: stránka na `ic-office-challenge.eu` zůstává statika na GitHub Pages, ale data (otázky, výsledky, fotky) žijí v Supabase místo Google Sheets a localStorage.

## 1. Založ projekt

1. Jdi na <https://supabase.com> a přihlas se (GitHub login funguje).
2. **New project**:
   - **Name:** `ic-office-challenge`
   - **Database password:** vygeneruj silné heslo a **ulož** ho do password manageru (heslo k Postgres DB, budeš ho potřebovat jen výjimečně).
   - **Region:** **Frankfurt (eu-central-1)** — nejnižší latence pro ČR.
   - **Pricing plan:** Free.
3. Počkej ~2 minuty, než projekt naběhne.

## 2. Spusť migrace

1. Vlevo v menu klikni na **SQL Editor** → **New query**.
2. Otevři soubor `supabase/migrations/0001_initial_schema.sql` z repa, **zkopíruj celý obsah** a vlož do editoru.
3. Klikni **Run** (Ctrl+Enter). Mělo by hlásit „Success. No rows returned".
4. Stejně postupuj s `supabase/migrations/0002_seed_default_challenge.sql`.
5. Kontrola: **Table Editor** → uvidíš tabulky `challenge`, `questions`, `results`. V `challenge` 1 řádek (slug `default`), v `questions` 15 řádků.

## 3. Vytvoř Storage bucket pro fotky otázek

1. Vlevo **Storage** → **New bucket**.
2. **Name:** `question-images`
3. **Public bucket:** **ON** (zaškrtnuté) — fotky jsou veřejně čitelné odkazem.
4. Klikni **Create bucket**.

Teď nastavíme policies — kdo smí do bucketu nahrávat / mazat:

5. V bucketu klikni na **Policies** → **New policy** → **For full customization**.
6. Vytvoř tři policies (jednu po druhé):

**Policy 1 — public read:**
```sql
-- Name: question-images public read
-- Allowed operation: SELECT
-- Target roles: anon, authenticated
-- USING expression:
bucket_id = 'question-images'
```

**Policy 2 — admin upload:**
```sql
-- Name: question-images admin upload
-- Allowed operation: INSERT
-- Target roles: authenticated
-- WITH CHECK expression:
bucket_id = 'question-images'
```

**Policy 3 — admin delete:**
```sql
-- Name: question-images admin delete
-- Allowed operation: DELETE
-- Target roles: authenticated
-- USING expression:
bucket_id = 'question-images'
```

> Pokud Supabase UI nabízí předpřipravené templates "Allow access to authenticated users only" pro INSERT/DELETE a "Public read" pro SELECT, můžeš použít je — udělají to samé.

## 4. Vytvoř admin účet

1. Vlevo **Authentication** → **Users** → **Add user** → **Create new user**.
2. **Email:** tvůj admin email
3. **Password:** silné heslo (toto budeš zadávat v admin režimu na webu)
4. **Auto confirm user:** ON (zaškrtnuto — nebude se posílat ověřovací email)
5. **Create user**.

> Důležité: v Supabase **Authentication → Settings → Email Auth → Enable email signups** **VYPNI** (`OFF`). Tím zabráníš tomu, aby si kdokoli z internetu vytvořil "admin" účet. Adminové se přidají vždy ručně přes Authentication → Add user.

## 5. Pošli mi klíče

Vlevo **Project Settings (ozubené kolečko)** → **API**:

- **Project URL** → zkopíruj (např. `https://abcdefghij.supabase.co`)
- **Project API keys → `anon` `public`** → zkopíruj (dlouhý JWT začínající `eyJ...`). **Tento klíč JE bezpečné dát do veřejného JS** — chrání ho RLS policies.
- **NIKOMU** neposílej `service_role` klíč — ten je tajný a obchází RLS.

Pošli mi:
```
SUPABASE_URL=https://...supabase.co
SUPABASE_ANON_KEY=eyJ...
ADMIN_EMAIL=tvuj@email.cz
```

(Heslo k admin účtu si nech, to budeš zadávat ty na webu.)

## 6. Co bude dál

Až mi tyhle 3 hodnoty pošleš, naváže fáze 2: upravím `index.html` tak, aby:
- Načítal otázky a config z `challenge` + `questions` v Supabase
- Ukládal výsledky do `results` (místo Google Sheets)
- V admin režimu používal Supabase Auth (místo hesla `6371` v JS)
- Měl upload fotek do Storage `question-images`

Pak fáze 3 (admin CRUD pro otázky a config), fáze 4 (public leaderboard s real-time efekty + YouTube mód), fáze 5 (mobile polish).
