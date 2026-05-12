# Dvoufaktorové ověření (MFA / 2FA) pro admina

Admin přístup k IC Office Challenge ovládá **veškerá data** — výsledky kvízu,
otázky, registrované účastníky, hudbu, materiály. Pokud někomu unikne heslo,
celá databáze je v ohrožení.

Supabase Auth nabízí built-in TOTP MFA — admin musí při přihlášení zadat
e-mail + heslo **+ jednorázový kód** z Authenticator aplikace
(Google Authenticator, Authy, 1Password, Microsoft Authenticator).

## Zapnutí MFA pro existující admin účet

1. **Otevři Supabase Auth UI** — `qa.html?admin=1` (nebo `/?admin=1` pro kvíz admin)
   a přihlas se e-mailem + heslem.
2. Aktuálně frontend **MFA enrollment UI ještě nemá** — je třeba ji zapnout
   z Supabase Dashboardu pomocí jednorázového skriptu (viz níže).

### Varianta A) Zapnout přes Supabase Dashboard

1. <https://supabase.com/dashboard> → tvůj projekt **IC Office Challenge**.
2. **Authentication → Multi-Factor Authentication** (v menu CONFIGURATION).
3. Přepni **Enable MFA** na ON. Vyber `TOTP` (Time-based One-Time Password).
4. **Save**.

> Tím se aktivuje schopnost MFA, ale **každý admin musí ještě enroll svůj
> Authenticator** — viz Varianta B níže.

### Varianta B) Enrollment admina (pro každý admin účet)

Frontend kvíz / Q&A admin login zatím nemá UI pro enrollment. Pro zápis MFA
faktoru použij **konzoli prohlížeče** po přihlášení do `qa.html?admin=1`:

```javascript
// 1) Vyžádej si nový MFA factor
const { data, error } = await supabaseClient.auth.mfa.enroll({ factorType: 'totp' });
if (error) console.error(error);
console.log('QR URL:', data.totp.qr_code);  // datauri PNG s QR kódem
console.log('Secret:', data.totp.secret);   // pro ruční zápis do Authy

// 2) Naskenuj QR kód v Google Authenticator / Authy / 1Password
//    nebo přepiš ručně secret. Aplikace začne generovat 6místné kódy.

// 3) Pošli první kód do verify endpointu (otevři Authenticator a opiš)
const code = '123456'; // ← aktuální 6místný kód z Authenticator
const ver = await supabaseClient.auth.mfa.challengeAndVerify({
  factorId: data.id,
  code
});
console.log('Enrolled:', ver);
```

Po `Enrolled: { ... }` je faktor aktivní a admin musí při příštím přihlášení
zadat 6místný kód.

### Varianta C) Doplnit MFA challenge UI do qa.html

To je už větší frontend úprava. Krátká specifikace pro budoucí session:

1. Po `signInWithPassword` zkontrolovat `auth.mfa.listFactors()`.
2. Pokud má účet aktivní TOTP faktor, místo přepnutí do admin panelu
   ukázat input pro 6místný kód.
3. Po zadání kódu zavolat `auth.mfa.challenge()` → dostaneš `challenge.id`,
   pak `auth.mfa.verify({ factorId, challengeId, code })`.
4. Až po úspěšné verifikaci přejít do admin režimu.

Tato část **není v current codebase implementovaná** — je to TODO pro F23
(Auth flow s MFA challengem).

## Recovery codes

Supabase Auth zatím nemá vestavěné recovery codes pro TOTP. Pokud admin
přijde o Authenticator (ztracený telefon), jediná možnost je:

1. Přihlásit se do Supabase Dashboard **vlastníkem projektu** (= admin email,
   který má přístup do účtu).
2. **Authentication → Users → vybrat účet → Edit → Reset MFA factors**.
3. Admin se přihlásí znovu jako bez MFA a enrolne nový faktor.

**Doporučení:** mít víc admin účtů (např. dva lidi z týmu), aby vždy aspoň
jeden mohl restartovat MFA tomu druhému.

## Best practices

- ✅ Použij **Authy** nebo **1Password** místo Google Authenticator —
  zálohují codes do cloudu, takže nový telefon znamená 5 min setup, ne katastrofa.
- ✅ Ulož QR kód z enrollmentu do password manageru jako PNG — můžeš ho
  použít k re-enrollu na druhém zařízení (např. tablet vedle telefonu).
- ❌ **Neuložit secret v rámci IC Office Challenge repa** — patří jen do
  password manageru.
- ✅ Při odchodu admina z týmu → smazat jeho účet **a** odebrat MFA factor.

## Související fáze

- **F23 (TODO):** přidat MFA challenge UI do `qa.html?admin=1` a `index.html`
  admin login, aby admini nemuseli enrollovat přes browser console.
