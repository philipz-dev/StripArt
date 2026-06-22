# StripArt — Checklist na Apple-goedkeuring

**Status nu:** wachten op goedkeuring naam- + adresdocument  
**Doel:** Paid Apps Agreement actief → paywall testen via TestFlight  
**Account:** Philip Zvar · Aarschot, België · geen zelfstandige (trader = Ja voor Apple)

---

## Fase 0 — Wachten (nu)

- [X] Naamdocument (eID/paspoort) ingediend
- [X] Adresdocument (rekening) ingediend
- [ ] E-mail van Apple ontvangen: documenten goedgekeurd
- [ ] **Paid Apps Agreement** status = **Active** (was: New)
- [ ] **Free Apps Agreement** blijft Active

> **Tip:** Check dagelijks App Store Connect → **Agreements, Tax, and Banking**

---

## Fase 1 — Wizard afronden (als Apple nog stappen vraagt)

### Bankgegevens

- [ ] IBAN ingevuld (Belgische rekening)
- [ ] Rekeninghouder = **Philip Zvar**
- [ ] Bankgegevens opgeslagen

### Belasting (U.S. Tax)

- [ ] Formulier **W-8BEN** ingevuld
- [ ] Land: **Belgium**
- [ ] Geen U.S. person / geen U.S. taxpayer
- [ ] Formulier ingediend

### BTW / VAT

- [ ] Geen BTW-nummer → optie “I don’t have a VAT number” gekozen (indien van toepassing)

### DSA / Trader (EU)

- [ ] Trader-status ingevuld: **Ik ben een trader**
- [ ] Naam: Philip Zvar
- [ ] Adres: Aarschot (zelfde als in account)
- [ ] Telefoonnummer ingevuld
- [ ] E-mail ingevuld (bereikbaar voor klanten)
- [ ] Opgeslagen

---

## Fase 2 — App Store Connect: In-App Purchase

Ga naar: **Apps → StripArt → Monetization → In-App Purchases**

- [ ] Nieuw product aangemaakt
- [ ] Type: **Non-Consumable**
- [ ] Product ID: `com.philip.stripart.unlock` *(exact, geen spelfout)*
- [ ] Reference Name: Unlock Unlimited Exports
- [ ] Display Name: Unlock Unlimited Exports
- [ ] Description: Unlock unlimited animation exports.
- [ ] Prijs: **€1,99** (of gewenste tier)
- [ ] Review screenshot paywall geüpload
- [ ] Status product: **Ready to Submit**
- [ ] 15–60 min gewacht (product propagatie)

---

## Fase 3 — Sandbox-testaccount

Ga naar: **Users and Access → Sandbox → Test Accounts**

- [ ] Nieuw sandbox-account aangemaakt
- [ ] Nieuw e-mailadres gebruikt (niet je echte Apple ID)
- [ ] Wachtwoord genoteerd op veilige plek
- [ ] Land: België

**Op iPhone (later bij testen):**

- [ ] Instellingen → App Store → **Sandbox Account** → ingelogd met testaccount

---

## Fase 4 — Build uploaden (TestFlight)

### In Xcode

- [ ] Scheme: **StripArt** (niet Sandbox)
- [ ] Versie: **1.0** · Build: **6** of hoger *(buildnummer verhogen bij elke upload)*
- [ ] **Product → Archive**
- [ ] **Distribute App → App Store Connect → Upload**
- [ ] Upload geslaagd

### In App Store Connect

- [ ] TestFlight → build zichtbaar
- [ ] Processing voltooid (groen vinkje)
- [ ] Export Compliance ingevuld (meestal: geen custom encryptie)
- [ ] Jezelf toegevoegd als **Internal Tester**
- [ ] TestFlight-uitnodiging geaccepteerd op iPhone
- [ ] StripArt geïnstalleerd via TestFlight-app

---

## Fase 5 — Paywall testen op iPhone

### Paywall triggeren

- [ ] App geopend via TestFlight (niet via Xcode)
- [ ] Foto gekozen → animatie gemaakt → opgeslagen
- [ ] Herhaald tot **5 exports** verbruikt
- [ ] Badge toont: **“No free animations left”**
- [ ] Save-knop opent **paywall**

### Aankoop (Sandbox)

- [ ] **Unlock for €1,99** getikt
- [ ] Ingelogd met **sandbox-testaccount**
- [ ] Aankoop bevestigd (gratis in sandbox)
- [ ] Export slaagt direct na unlock
- [ ] Geen limiet meer na unlock

### Restore

- [ ] App verwijderd en opnieuw geïnstalleerd via TestFlight
- [ ] Paywall opnieuw getriggerd (5 exports opnieuw nodig, of al verbruikt)
- [ ] **Restore Purchase** getikt
- [ ] Unlock hersteld zonder nieuwe aankoop

### Extra scenario’s

- [ ] **Maybe later** sluit paywall, geen export
- [ ] Prijs klopt (€1,99 of store-prijs)
- [ ] Geen foutmelding “Could not load the store”
- [ ] Geen foutmelding “The unlock is not available right now”

---

## Fase 6 — Testen (volledige app)

Test op een **echte iPhone via TestFlight** (niet via Xcode/simulator).

### Setup & foto

- [ ] App opent zonder crash
- [ ] Resolutie (hoogte × breedte) invullen werkt
- [ ] Ongeldige resolutie blokkeert doorgaan
- [ ] **Import Photo** opent fotobibliotheek
- [ ] **Take Photo** opent camera (op device met camera)
- [ ] Tips-scherm verschijnt (eerste keer)
- [ ] “Do not show again” onthoudt keuze

### Crop — start & eind

- [ ] Richting kiezen (↑ ↓ ← →) werkt
- [ ] Startfase: frame verplaatsen werkt
- [ ] Startfase: hoeken slepen verandert formaat
- [ ] Startfase: zoom-slider vergroot/verkleint
- [ ] Startfase: bevestigen → eindfase
- [ ] Eindfase: frame slepen in gekozen richting
- [ ] Richting wisselen reset naar startpositie
- [ ] Annuleren in eindfase → terug naar startfase
- [ ] Annuleren in startfase → terug naar hoofdscherm (foto gewist)

### Frame rate & appearance

- [ ] Frame rate slider past animatiesnelheid aan
- [ ] Preview animatie speelt vloeiend af
- [ ] Dithering-algoritme wisselen werkt
- [ ] Contrast-slider past beeld aan
- [ ] Terug-knoppen navigeren correct door flow

### Preview & export

- [ ] Animatie preview zichtbaar en speelt af
- [ ] **Save** slaat GIF op in fotobibliotheek
- [ ] Toestemming fotobibliotheek gevraagd (eerste keer)
- [ ] Succes-overlay verschijnt na opslaan
- [ ] Terug naar hoofdscherm na bevestiging
- [ ] **Share** deelt GIF via share sheet
- [ ] Badge “Free animations left: X” klopt (1–5)

### Paywall & IAP (Sandbox)

- [ ] Na 5 exports: paywall verschijnt bij Save
- [ ] Prijs getoond (€1,99 of store-prijs)
- [ ] **Unlock** → sandbox-aankoop → export slaagt
- [ ] Na unlock: geen limiet meer
- [ ] **Restore Purchase** herstelt unlock na herinstallatie
- [ ] **Maybe later** sluit paywall zonder export
- [ ] Geen store-foutmeldingen

### Edge cases & stabiliteit

- [ ] App overleeft background/foreground wissel
- [ ] Grote foto’s laden zonder crash
- [ ] Portret-orientatie blijft correct
- [ ] Geheugengebruik oké bij lange sessie (meerdere animaties)
- [ ] Geen vastloper bij snel heen-en-weer navigeren

### Verschillende devices (indien mogelijk)

- [ ] Getest op minimaal 1 fysiek iPhone-model
- [ ] UI leesbaar op kleiner scherm (bijv. iPhone SE / mini)
- [ ] UI leesbaar op groter scherm (bijv. Pro Max)

---

## Fase 7 — To do voor het indienen

### App Store Connect — app-pagina

- [ ] App-naam: **StripArt**
- [ ] Ondertitel ingevuld (max. 30 tekens)
- [ ] Beschrijving geschreven (NL + EN indien meertalig)
- [ ] Keywords ingevuld
- [ ] Support URL ingevuld (e-mail of website)
- [ ] Privacy Policy URL ingevuld *(verplicht bij foto/camera-toegang)*
- [ ] Categorie gekozen (bijv. Photo & Video)
- [ ] Leeftijdsclassificatie ingevuld (vragenlijst)
- [ ] App-privacy (Privacy Nutrition Labels) ingevuld:
  - [ ] Fotobibliotheek (gebruik + opslag)
  - [ ] Camera (indien van toepassing)
  - [ ] Geen tracking

### Screenshots & media

- [ ] Screenshots iPhone 6.7" (Pro Max) — min. 3 stuks
- [ ] Screenshots iPhone 6.5" of 6.1" — min. 3 stuks
- [ ] App Preview video *(optioneel)*
- [ ] App Store-icoon klopt (1024×1024 via Assets)

### In-App Purchase (review)

- [ ] IAP `com.philip.stripart.unlock` status: **Ready to Submit**
- [ ] IAP review screenshot (paywall) geüpload
- [ ] IAP **gekoppeld aan versie 1.0** vóór indienen
- [ ] Restore-knop zichtbaar in paywall *(App Review vereiste)*

### Build & versie

- [ ] Versie **1.0** aangemaakt in App Store Connect
- [ ] Laatste TestFlight-build geselecteerd voor submission
- [ ] Buildnummer uniek en hoger dan vorige upload
- [ ] Export Compliance ingevuld
- [ ] Geen debug-code of test-flags in Release build

### Juridisch & compliance

- [ ] DSA/trader-gegevens ingevuld en zichtbaar voor EU
- [ ] Paid Apps Agreement = **Active**
- [ ] W-8BEN ingediend
- [ ] Privacy policy online en bereikbaar
- [ ] Contactgegevens kloppen met trader-info

### Review-notities voor Apple

- [ ] Demo-account niet nodig (app werkt zonder login)
- [ ] Review Notes: uitleg paywall — “5 gratis exports, daarna eenmalige unlock”
- [ ] Review Notes: hoe paywall te triggeren (5× opslaan)
- [ ] Sandbox-testaccount-credentials *(alleen indien Apple erom vraagt)*

### Laatste check vóór Submit

- [ ] Alle TestFlight-tests afgevinkt (Fase 6)
- [ ] Geen open crashes of blockers
- [ ] App getest op schone installatie (verwijder → herinstalleer)
- [ ] **Submit for Review** geklikt
- [ ] E-mail App Review-notificaties aan staan

### Na indienen

- [ ] Status “Waiting for Review” bevestigd
- [ ] Eventuele vragen van App Review beantwoord
- [ ] Bij afkeuring: feedback gelezen → fix → nieuwe build uploaden
- [ ] Bij goedkeuring: release handmatig of automatisch gepland

---

## Snelle referentie

| Item | Waarde |
|---|---|
| Bundle ID | `com.philip.stripart` |
| Product ID | `com.philip.stripart.unlock` |
| Gratis exports | 5 |
| Team ID | `PB4953L2J4` |
| Xcode scheme (lokaal) | StripArt (met .storekit) |
| Xcode scheme (device sandbox) | StripArt Sandbox |
| TestFlight | echte App Store Connect IAP |

---

## Problemen? Snelle fixes

| Symptoom | Actie |
|---|---|
| Paid Apps blijft New | Wacht op documentgoedkeuring; check e-mail Apple |
| IAP niet beschikbaar | Product ID controleren; 15–60 min wachten |
| Geen sandbox-login | Instellingen → App Store → Sandbox Account |
| “Could not load store” | Paid Apps Agreement moet Active zijn |
| Build rejected processing | Export compliance / Info.plist controleren |

---

## Volgorde in één oogopslag

```
Wachten op goedkeuring
    ↓
Paid Apps Agreement = Active
    ↓
Bank + W-8BEN + DSA/trader
    ↓
IAP aanmaken (com.philip.stripart.unlock)
    ↓
Sandbox-testaccount
    ↓
Archive → TestFlight upload
    ↓
5 exports → paywall → unlock → restore (Fase 5)
    ↓
Volledige app testen (Fase 6)
    ↓
App Store-pagina + IAP + screenshots (Fase 7)
    ↓
Submit for Review → live in App Store
```
