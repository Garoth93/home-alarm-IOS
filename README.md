# Antifurto — comandi SMS per l'antifurto di casa (iOS)

App iOS nativa (Swift + SwiftUI, grafica Material 3) per inserire e
disinserire l'antifurto di casa inviando SMS alla centralina. Include widget
per la schermata Home e la schermata di blocco, un pulsante per il Centro di
Controllo e il tasto Azione, i comandi Siri e una pagina di statistiche.

Sviluppata senza Mac: compilata da GitHub Actions e installata sull'iPhone con
un account Apple gratuito tramite Sideloadly o SideStore.

[![build-ipa](https://github.com/Garoth93/home-alarm-IOS/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/Garoth93/home-alarm-IOS/actions/workflows/build-ipa.yml)
[![test-linux](https://github.com/Garoth93/home-alarm-IOS/actions/workflows/test-linux.yml/badge.svg)](https://github.com/Garoth93/home-alarm-IOS/actions/workflows/test-linux.yml)

## Come funziona

La centralina riceve SMS del tipo `<comando> <password>`, ad esempio:

| Pulsante        | Comando        | SMS inviato           |
|-----------------|----------------|-----------------------|
| Totale          | `attiva 1-2-3` | `attiva 1-2-3 1966`   |
| Notte           | `attiva 1-2`   | `attiva 1-2 1966`     |
| **Disinserisci**| `disattiva`    | `disattiva 1966`      |

Nell'app configuri:

1. **Case**: nome, icona, colore, **numero** della centralina e **password**.
   Numero e password si inseriscono una sola volta e vengono aggiunti a ogni
   comando. La password resta nel portachiavi dell'iPhone.
2. **Comando di disinserimento** (uno per casa, es. `disattiva`) e, se la
   centralina lo supporta, un comando di **stato**.
3. **Zone**: ogni zona ha un nome e la sua combinazione (`attiva 1-2-3`, …).
4. **Formato SMS**: predefinito `{comando} {password}`; si può cambiare
   (es. `{password} {comando}`).

Tocchi una zona o "Disinserisci": si apre Messaggi con l'SMS già pronto e premi
**Invia**. iOS non permette a nessuna app di inviare SMS senza la tua conferma.
L'esito (inviato / annullato) finisce nello **storico**.

## Cosa c'è

- **Antifurto**: stato della casa (inserito / disinserito, quale zona, da
  quanto), pulsante grande Disinserisci, griglia delle zone, ultimi comandi.
  Lo stato è dedotto dall'ultimo SMS inviato: se hai agito dal telecomando lo
  correggi dal menu "…" della card, senza inviare SMS.
- **Storico**: tutti i comandi raggruppati per giorno, filtri per tipo e casa,
  esito e origine (app, widget, Centro di Controllo, Siri). Scorri per eliminare.
- **Statistiche** (7 g / 30 g / 90 g / 1 anno / tutto): tempo protetto e
  percentuale, SMS inviati, inserimenti, disinserimenti, durata media, serie di
  giorni, zone più usate con tempo inserito, grafico attività, orari tipici,
  giorni della settimana, da dove invii i comandi.
- **Impostazioni**: più case, conferma prima dell'SMS, **Face ID per
  disinserire**, casa predefinita per i widget, tema chiaro/scuro, backup e
  ripristino JSON (con o senza password), export CSV dello storico.

### Widget e controlli

| Dove | Widget | Cosa fa |
|------|--------|---------|
| Home, piccolo | **Antifurto** | stato + tocco = Disinserisci |
| Home, medio | **Antifurto** | stato, Disinserisci, prime 3 zone |
| Home, grande | **Antifurto** | stato, Disinserisci, fino a 6 zone, stato centralina |
| Home, piccolo | **Comando rapido** | un comando a scelta (Disinserisci o una zona) |
| Schermata di blocco | **Antifurto** / **Comando rapido** | stato o comando con un tocco |
| Centro di Controllo / tasto Azione | **Antifurto** | comando a scelta |
| Siri / Comandi | "Comando Antifurto" | comando a scelta |

Ogni widget si configura tenendolo premuto → **Modifica widget** (casa o
comando). Il tocco apre l'app con l'SMS già pronto.

## Installare l'app sull'iPhone

### 1. Scaricare il `.ipa`

1. Pagina **Actions** della repo → workflow **build-ipa**.
2. Apri l'ultimo run verde (o avvialo con **Run workflow**).
3. In fondo, sezione **Artifacts**, scarica `HomeAlarm-unsigned-ipa` ed
   estrai `HomeAlarm-unsigned.ipa`. Resta disponibile 30 giorni.

### 2. Firmare e installare con Sideloadly

1. Collega l'iPhone via USB, sbloccalo e scegli "Autorizza".
2. Apri Sideloadly e trascina `HomeAlarm-unsigned.ipa` nella finestra.
3. Inserisci l'Apple ID e premi **Start**.
4. Sull'iPhone: Impostazioni → Generali → **VPN e gestione dispositivo** →
   il tuo Apple ID → **Autorizza**. Serve anche la **Modalità sviluppatore**.

### 3. Primo avvio

Tocca **Crea la tua casa**: trovi già le zone d'esempio (Totale `attiva 1-2-3`,
Notte `attiva 1-2`, Perimetrale `attiva 1`) da adattare alla tua centralina.
Inserisci numero e password e salva.

In **Impostazioni → Widget e controlli** controlla la riga "Dati condivisi con i
widget". Se dice **Non disponibili**, la firma non ha incluso l'App Group: i
widget funzionano lo stesso, ma mostrano solo "Disinserisci" della casa
predefinita. Riprova a firmare con SideStore oppure, in Sideloadly,
controlla di non aver attivato opzioni che rimuovono le estensioni.

### 4. Limiti dell'account gratuito

- La firma scade dopo **7 giorni**: rifirma lo stesso `.ipa` (il bundle ID
  `com.garoth93.homealarm` non cambia, i dati restano).
- Massimo **3 app** firmate attive per Apple ID. Se ne hai già 3, usa un
  secondo Apple ID per questa app o rimuovine una (prima fai il backup dei
  suoi dati).
- L'app e il widget usano **2 identificativi** (app + estensione) del limite di
  10 nuovi identificativi ogni 7 giorni.
- I dati restano solo sul telefono: fai un **backup JSON** dalle Impostazioni
  prima di reinstallare. Le password sono nel portachiavi: includile nel
  backup se vuoi ripristinarle su un altro iPhone.

## Struttura

```
apps/HomeAlarm/        app SwiftUI (project.yml per XcodeGen)
  Sources/             schermate e logica dell'app
  Shared/              codice comune app + widget (tema, dati condivisi, intent)
  Widgets/             estensione WidgetKit (widget e controllo)
  *.entitlements       App Group per la firma
packages/AlarmCore/    logica non grafica, testata con `swift test` anche su Linux
.github/workflows/     build-simulator, build-ipa, test-linux
CLAUDE.md              convenzioni e regole di lavoro per Claude Code
```

---

# instaStats per iPhone

Versione iPhone di [insta-statistics](https://github.com/Garoth93/insta-statistics):
capisci chi ti segue su Instagram partendo dall'**export ufficiale**. Non serve
dare la password a nessuno e i dati restano sul telefono.

1. **Scarica l'export**: Instagram › Impostazioni › Centro gestione account ›
   Le tue informazioni e autorizzazioni › Scarica le tue informazioni › solo
   "Follower e persone seguite", formato **JSON**.
2. **Importa** lo ZIP dall'app File (o "Condividi › instaStats"). Ogni import
   diventa un'**istantanea**.
3. **Rivedi** i *Non ricambiano* a schede: scorri a **sinistra per tenere**, a
   **destra per smettere di seguire**. Annulla sempre disponibile.
4. **Smetti di seguire**: la sessione apre i profili uno alla volta su Instagram.
   Al prossimo import chi non segui più perde il segno da solo.
5. **Ripeti ogni tanto**: con due istantanee compaiono *Follower persi*,
   *Nuovi follower*, *Nuovi seguiti*, *Non segui più* e il grafico.

Liste: Non ricambiano, Fan, Reciproci, Follower, Seguiti, Richieste in sospeso,
Nuovi follower, Follower persi, Nuovi seguiti, Non segui più, Da smettere di
seguire, Tenuti, Amici stretti, Smessi di recente. Ognuna si cerca, si ordina,
si esporta in CSV; scorri una riga per tenere / smettere, "Seleziona" per
agire su molti account insieme. Il dettaglio mostra da quando vi seguite, la
nota e lo storico nelle istantanee.

**Dal PC**: in Altro › *Importa da instaStats desktop* scegli il file
`instastats.db` (copialo prima in iCloud Drive): istantanee, segni e note
arrivano sul telefono.

Installazione: workflow **build-ipa** › artifact `InstaStats-unsigned-ipa` ›
Sideloadly, come per Antifurto.
