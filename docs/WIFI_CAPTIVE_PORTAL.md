# WiFi captive portal → IC Office školení

Tento dokument popisuje, jak nakonfigurovat **router/firewall na pobočce IC Office** tak, aby každý kdo se připojí na WiFi byl automaticky přesměrován na registrační stránku školení.

## Jak to bude fungovat

```
┌─────────────┐   1. připojení na WiFi „IC Office"      ┌────────────┐
│  účastník   │ ─────────────────────────────────────▶  │   router   │
│ (telefon)   │                                          │ + captive  │
└─────────────┘ ◀──── 2. redirect na URL ────────────── │   portal   │
       │                                                  └────────────┘
       │
       │  3. otevře se /qa.html?session=<slug>
       ▼
┌────────────────────────────────────────────────────────────────────┐
│ Registrační formulář (IC Office Challenge)                          │
│ — vyplní CXXXXX / firma / IČ / email / telefon                      │
│ — po odeslání pokračuje na Q&A (intro fáze / live / outro)          │
└────────────────────────────────────────────────────────────────────┘
```

## Společné předpoklady

- **WiFi SSID:** např. `IC-Office-Skoleni` (zviditelněte, bez hesla nebo s heslem, které dáte do programu)
- **Cílová URL pro redirect:**
  ```
  https://www.ic-office-challenge.eu/qa.html?session=<slug-vaší-session>
  ```
  `<slug-vaší-session>` se shoduje se slugem, který jste založili v admin panelu (`/qa.html?admin=1`).

- **Povolené domény** mimo whitelist (aby qa stránka mohla volat backend):
  - `*.supabase.co` (Supabase REST + Storage + Realtime)
  - `cdn.jsdelivr.net` (knihovny: Supabase JS, qrcode, jsPDF, …)
  - `view.officeapps.live.com` (PowerPoint Web Viewer pro slidy)
  - `www.youtube.com`, `youtube.com`, `i.ytimg.com` (intro/outro video)
  - `docs.google.com`, `drive.google.com` (Google Slides / PDF embed)
  - `www.ic-office.eu` (footer link a OG)

Bez whitelistu Supabase + jsDelivr **vám stránka nepojede** ani po proklikání captive portalem.

---

## A) Ubiquiti UniFi (UniFi Network Controller)

Nejjednodušší prostředí; ideální pro pobočky s UniFi accesspointy.

1. Přihlásit se do **UniFi Network** (controller).
2. **Settings → WiFi → Create New Network**.
3. **Network Name:** `IC-Office-Skoleni`. **Security Protocol:** `Open` (nebo `WPA2` se sdíleným heslem).
4. **Advanced → Hotspot 2.0 / Guest Hotspot:** zapnout **Use as Guest Network**.
5. **Settings → Profiles → Guest Hotspot**:
   - **Authentication:** `External Portal Server` (External Captive Portal).
   - **Portal URL:** `https://www.ic-office-challenge.eu/qa.html?session=<slug>`
   - **Allowed Domains:** doplnit všechny domény ze sekce „Společné předpoklady".
   - **Redirect URL after authorization:** stejná URL nebo `https://www.ic-office-challenge.eu/`
6. **Save** a počkat ~30 s na deploy do APs.

> **Tip:** UniFi captive portal vyžaduje, aby váš webový server podepsal redirect. Pro V1 si můžete přidat odkaz „Pokračovat" v patičce formuláře, který triggerne `window.location = decodeURIComponent(new URLSearchParams(location.search).get('redirect')) || '/'`. Pro plně automatický flow je třeba implementovat External Portal API přesně podle UniFi docs.

---

## B) MikroTik (RouterOS)

Vlastní implementace „chillispot-like" hotspot s podporou redirectu.

1. Připojit se přes Winbox nebo SSH.
2. Vytvořit hotspot interface:
   ```
   /interface bridge add name=bridge-hotspot
   /interface bridge port add bridge=bridge-hotspot interface=ether2
   /ip address add address=10.50.50.1/24 interface=bridge-hotspot
   /ip pool add name=hotspot-pool ranges=10.50.50.10-10.50.50.250
   /ip dhcp-server add address-pool=hotspot-pool interface=bridge-hotspot disabled=no
   /ip dhcp-server network add address=10.50.50.0/24 gateway=10.50.50.1 dns-server=8.8.8.8
   ```
3. Vytvořit hotspot s redirectem:
   ```
   /ip hotspot setup
   ```
   Průvodce se zeptá na rozhraní, IP, pool, DNS, certifikát atd.
4. **Klíčový krok — Walled Garden (whitelist)** povolit Supabase + CDN domény před autentikací:
   ```
   /ip hotspot walled-garden add dst-host=*.supabase.co action=allow
   /ip hotspot walled-garden add dst-host=cdn.jsdelivr.net action=allow
   /ip hotspot walled-garden add dst-host=view.officeapps.live.com action=allow
   /ip hotspot walled-garden add dst-host=*.youtube.com action=allow
   /ip hotspot walled-garden add dst-host=docs.google.com action=allow
   /ip hotspot walled-garden add dst-host=www.ic-office-challenge.eu action=allow
   /ip hotspot walled-garden add dst-host=www.ic-office.eu action=allow
   ```
5. **Upravit login HTML** v MikroTik souboru `hotspot/login.html` — místo formuláře vložit:
   ```html
   <html><head><meta http-equiv="refresh"
        content="0; url=https://www.ic-office-challenge.eu/qa.html?session=<slug>" />
   </head><body></body></html>
   ```
6. **Walked garden trusted:** přidat doménu IC Office, aby uživatel mohl proklikat:
   ```
   /ip hotspot walled-garden ip add dst-host=www.ic-office-challenge.eu action=accept
   ```

---

## C) TP-Link Omada (OC200 / OC300 / Software Controller)

1. **Settings → Authentication → Portal**.
2. **Create new Portal**:
   - **Portal Type:** `External Web Portal`
   - **External Portal Server URL:** `https://www.ic-office-challenge.eu/qa.html?session=<slug>`
   - **Authentication Timeout:** 4 hodiny (= délka jedné akce)
3. **Pre-Authentication Access List:** přidat hostnames ze sekce „Společné předpoklady".
4. **WiFi SSID → Settings → Portal Authentication:** vybrat právě vytvořený portal.
5. Save & Apply.

---

## D) OpenWrt + nodogsplash

Pro DIY router s OpenWrt.

1. Nainstalovat:
   ```bash
   opkg update
   opkg install nodogsplash
   ```
2. Editovat `/etc/nodogsplash/nodogsplash.conf`:
   ```
   GatewayInterface br-lan
   MaxClients 200
   ClientIdleTimeout 240
   PreAuthIdleTimeout 30

   AuthIdleTimeout 240
   RemoteAuthenticatorAction https://www.ic-office-challenge.eu/qa.html?session=<slug>

   # Walled garden
   FirewallRuleSet preauthenticated-users {
     FirewallRule allow tcp port 443 to *.supabase.co
     FirewallRule allow tcp port 443 to cdn.jsdelivr.net
     FirewallRule allow tcp port 443 to view.officeapps.live.com
     FirewallRule allow tcp port 443 to *.youtube.com
     FirewallRule allow tcp port 443 to docs.google.com
     FirewallRule allow tcp port 443 to www.ic-office-challenge.eu
     FirewallRule allow tcp port 443 to www.ic-office.eu
   }
   ```
3. Restartovat:
   ```bash
   /etc/init.d/nodogsplash restart
   ```

---

## E) Co když nemám router s captive portal funkcí?

Funguje i bez něj — stránka `qa.html` se chová jako stand-alone formulář.
Alternativy:

1. **QR kód na vstupu / projektoru.** Účastník nascannuje a otevře `qa.html?session=<slug>` ručně. Bez WiFi konfigurace.
2. **Otevřená WiFi + tisknutý leták s URL.**
3. **Krátký link.** Použij `bit.ly` nebo `tinyurl.com` na URL `https://www.ic-office-challenge.eu/qa.html?session=brno-2026`. Účastník napíše do prohlížeče.

> **Doporučení pro V1**: spustit školení s **QR kódem** na vstupu nebo na projektoru. Captive portal řešit až po pár školeních, až budeš mít pevný router.

---

## Testovací postup pro nový router

1. Otevři `qa.html?admin=1` → vytvoř testovací session s `slug = test-wifi`.
2. Připoj se na WiFi telefonu, který **nikdy předtím nepoužil** přihlášení (clean state).
3. Sleduj, zda systém:
   - automaticky otevře browser (Android / iOS to dělá pro neauthorized clients),
   - přesměruje na `qa.html?session=test-wifi`,
   - umožní stisknout formulář (Supabase POST funguje → router povolil),
   - po submitu pustí klienta do internetu (= dovoluje opustit captive režim).

Pokud první 2 kroky fungují, ale formulář selže → chybí whitelist domén. Vrať se k seznamu v „Společné předpoklady".

---

## Bezpečnostní poznámky

- Captive portal **nepoužívej s admin URL** (`?admin=1`). Admin přístup je přes Supabase Auth — heslo by jsi nikdy neměl/a předávat účastníkům.
- Po skončení akce **smaž testovací session** přes admin panel (Smazat session) — odebere všechny dotazy, hlasy, registrované účastníky.
- Pokud chceš mít WiFi i pro běžný provoz pobočky, zvol **separátní SSID** „IC-Office-Skoleni" s vlastním VLAN.
