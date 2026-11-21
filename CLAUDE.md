# CLAUDE.md — regole di lavoro per questa repo

Repo di app iOS **native (Swift + SwiftUI)** personali, sviluppate senza Mac:
il codice viene scritto su Linux (Claude Code) e compilato **solo** su GitHub
Actions con runner macOS. Le app non vanno su App Store: l'utente scarica il
`.ipa` non firmato dagli artifact e lo firma con Sideloadly/SideStore.

Stessa impostazione delle repo `Garoth93/tracking-maintenance`,
`Garoth93/photo-system-IOS` e `Garoth93/LTIDI-Last-Time-I-Did-It-IOS`.

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView, niente framework cross-platform,
  salvo richiesta esplicita dell'utente.
- Nessun `.xcodeproj` committato: il progetto è generato in CI da
  `apps/<app>/project.yml` con XcodeGen. `.gitignore` lo esclude.
- La repo è **pubblica**: mai committare segreti, chiavi API, certificati,
  profili di provisioning, dati personali, Team ID reali.
- Account Apple gratuito: nessuna firma in CI (`CODE_SIGNING_ALLOWED=NO`).
- Non modificare impostazioni della repo o secrets: spiegare all'utente cosa
  configurare.

## Struttura repo

```
apps/<NomeApp>/            un'app per cartella
  project.yml              spec XcodeGen (target, bundle id, deployment target)
  Sources/                 codice SwiftUI dell'app (solo strato UI + glue)
  Resources/               Assets.xcassets e altre risorse
  Shared/                  codice comune app + widget (se c'è un'estensione)
  Widgets/                 estensione WidgetKit (se presente)
  *.entitlements           entitlements (App Group) usati per la firma ad-hoc in CI
  Info.plist               GENERATO da XcodeGen (git-ignored)
packages/<NomePackage>/    Swift Package con la logica NON grafica
  Package.swift            tools-version 5.9, nessuna dipendenza da UIKit/SwiftUI
  Sources/<NomePackage>/   modelli, regole, persistenza (Foundation only)
  Tests/<NomePackage>Tests/ XCTest, eseguiti anche su Linux
.github/workflows/         CI (vedi sotto)
.github/actions/setup-xcode/ composite action: seleziona Xcode, installa XcodeGen, genera il progetto
```

App presenti:

| App       | Package logica | Bundle ID                                  | Deployment target |
|-----------|----------------|--------------------------------------------|-------------------|
| HomeAlarm | AlarmCore      | `com.garoth93.homealarm` (+ `.widgets`)    | iOS 26.0 |
| InstaStats| InstaCore      | `com.garoth93.instastats`                  | iOS 26.0 |

HomeAlarm ("Antifurto" sulla Home): comanda l'antifurto di casa via **SMS**
alla centralina. Modello: **Casa** (numero di telefono, comando di
disinserimento univoco, comando stato facoltativo, formato SMS
`{comando} {password}`) → **Zone** (nome + combinazione, es. `attiva 1-2-3`).
La **password** sta a livello di casa, nel **Keychain** (`PasswordVault`),
mai nel JSON condiviso. Esempio: zona "Totale" = `attiva 1-2-3`, password
1966 → SMS `attiva 1-2-3 1966`.

- iOS non permette l'invio silenzioso: l'app apre `MFMessageComposeViewController`
  precompilato e l'utente preme Invia. Esito (inviato/annullato/fallito)
  registrato in `AlarmData.events` (messaggio salvato con password mascherata).
- Lo stato "inserito/disinserito" è **dedotto** dall'ultimo SMS inviato
  (`AlarmData.state(for:)`); correzione manuale dal menu della card di stato.
- Statistiche (`AlarmStats`): tempo protetto, inserimenti/disinserimenti,
  zone, orari, giorni della settimana, serie, origine (app/widget/controllo/Siri).
- Widget (target `HomeAlarmWidgets`, sorgenti in `Widgets/`): "Antifurto"
  (small/medium/large + lock screen) e "Comando rapido"; i pulsanti sono
  deep link `homealarm://run?action=<AlarmActionRef.id>&source=widget` che
  aprono l'app con l'SMS pronto. Controllo per Centro di Controllo / tasto
  Azione (`AlarmControl`, intent `ControlAlarmActionIntent`) e App Shortcuts
  Siri (`RunAlarmActionIntent`).
- `Shared/` è compilata in **entrambi** i target (tema, `SharedStore`, intent).
  Nel widget è definito `WIDGET_EXTENSION`: lì gli intent salvano un comando
  "pendente" nelle UserDefaults del gruppo, l'app lo esegue quando torna attiva.
- Dati condivisi via App Group `group.com.garoth93.homealarm`; il gruppo
  reale viene letto da `embedded.mobileprovision` (i firmatari gratuiti lo
  possono rinominare). Senza App Group l'app usa Application Support e i
  widget mostrano solo "Disinserisci" della casa predefinita.
- In CI il `.ipa` viene firmato **ad-hoc** con `HomeAlarm.entitlements` e
  `Widgets.entitlements` (step "Package unsigned .ipa") così Sideloadly vede
  l'App Group.

InstaStats ("instaStats" sulla Home): versione iPhone dell'app desktop
`Garoth93/insta-statistics` (Qt/QML, privata). Stessa logica, riscritta in Swift
nel package `InstaCore`:

- `ExportReader` + `MiniZip` (inflate in Swift puro, ZIP64, legge solo i JSON
  utili anche da export di GB): formati JSON vecchi, 2024+ e `label_values`
  2025, etichette IT/EN; proprietario da `personal_information.json` o dal
  nome `instagram-<utente>-AAAA-MM-GG-…`; HTML riconosciuto e rifiutato.
- `InstaData`: istantanee (`Snapshot`, liste per `Rel`) + segni per
  proprietario e username (`MarkInfo`: tieni / da smettere + nota). Import
  con firma anti-duplicati; i "da smettere" che non segui più si tolgono da
  soli; `il_mio_account` si unisce al primo proprietario reale.
- `Analysis`: confronto istantanea corrente / confronto, 14 liste
  (`ListKind`, stessi predicati di `AppController::inView` desktop),
  statistiche, sottotitoli, iniziali e colore avatar, CSV `;` con BOM.
- App: Panoramica (numeri, cambiamenti, grafico andamento), Liste (cerca,
  ordina, swipe tieni/da smettere, selezione multipla, CSV), **Rivedi** a
  schede (scorri a sinistra = tieni, a destra = da smettere, come Sweep) e
  sessione "Smetti di seguire" che apre i profili uno alla volta, Altro
  (import ZIP/cartella/JSON anche multipli, "Apri con" per gli ZIP,
  istantanee, rinomina account, backup JSON, import del DB SQLite della
  versione desktop `instastats.db` in `DesktopDatabase.swift`).
- Persistenza: `instastats.json` in Application Support (`JSONFileStore`),
  salvataggio differito.

Per aggiungere un'app: creare `apps/<Nome>/project.yml` + `Sources/` +
`Resources/`; i workflow scoprono automaticamente le cartelle in `apps/`
e i `Package.swift` in `packages/`. Il nome della cartella deve coincidere
con `name`, target e scheme nel `project.yml`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0` nel project.yml), tools-version
  5.9 nei package, in modo che Linux (`swift:6.0`) e Xcode 26 compilino lo
  stesso codice. Il package dichiara `.iOS(.v17)` come minimo: è solo il suo
  minimo, l'app può avere un target più alto.
- Logica, modelli e persistenza nel package: tipi `struct` value-type,
  `Codable`, `Equatable`, `Sendable`, senza `import SwiftUI`/`UIKit`.
  Tutto ciò che è testabile va lì e ha un test.
- Nell'app: `@Observable` (framework Observation) + `@MainActor`, iniettato
  con `.environment(...)` e letto con `@Environment(Tipo.self)`; viste piccole,
  una per file; stringhe UI in italiano. Target iOS 26.0: si possono usare
  SwiftData, Liquid Glass e le API SwiftUI di iOS 26 senza `#available`.
- Persistenza: JSON in Application Support tramite `JSONFileStore` (o
  SwiftData/UserDefaults quando serve, decidere caso per caso e documentarlo).
- Nessuna dipendenza esterna salvo necessità motivata; se serve, dichiararla
  nel `Package.swift` o in `project.yml > packages`, mai vendorizzare binari.
- Commit piccoli e descrittivi, in italiano o inglese ma coerenti; un commit
  per argomento. Niente identificatori di modello AI nei commit.

## Xcode e runner

- Runner: `macos-26`. Xcode fissato con `XCODE_VERSION: "26.6"` (SDK iOS 26.5) (env in ogni
  workflow) e selezionato con `xcode-select`. Se GitHub ritira la versione,
  la composite action fallisce elencando le Xcode disponibili: aggiornare il
  valore in tutti i workflow e qui.
- Toolchain Linux per i test: immagine Docker `swift:6.0-noble`.
- XcodeGen e xcbeautify installati con Homebrew a ogni run.

## CI (GitHub Actions)

| Workflow | Trigger | Cosa fa |
|----------|---------|---------|
| `build-simulator.yml` | push su ogni branch, PR, manuale | `xcodebuild build` per iOS Simulator, senza firma. Serve a vedere gli errori di compilazione. |
| `build-ipa.yml` | push su `main` e `claude/**`, manuale | build Release per dispositivo con `CODE_SIGNING_ALLOWED=NO`, firma ad-hoc con gli `.entitlements` dell'app e delle estensioni, impacchetta `Payload/<App>.app` in `<App>-unsigned.ipa` e lo carica come artifact (30 giorni). |
| `test-linux.yml` | push su ogni branch, PR, manuale | `swift test` su ogni package in `packages/`. |

Nota: nei repo pubblici i workflow con `schedule` vengono disattivati dopo 60
giorni senza commit. Se in futuro si aggiunge un rebuild periodico (utile per
la scadenza a 7 giorni della firma gratuita), prevedere un riattivatore o usare
`workflow_dispatch`.

### Come leggere i log di CI

Con `gh` (se il token è valido):

```bash
gh run list --limit 10
gh run view <run-id> --log-failed
gh run watch <run-id>
gh run download <run-id> -n HomeAlarm-unsigned-ipa   # oppure InstaStats-unsigned-ipa
```

Con gli strumenti GitHub MCP disponibili a Claude Code (quando `gh` non è
autenticato): `actions_list` con `list_workflow_runs` per trovare il run,
`list_workflow_jobs` per i job, `get_job_logs` con `failed_only=true` e
`return_content=true` per i log dei job falliti. I log raw di `xcodebuild`
sono anche caricati come artifact `xcodebuild-*-log-<App>`.

Gli errori Swift compaiono come annotazioni `::error file=...` grazie a
`xcbeautify --renderer github-actions`.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare l'esito della CI e correggere da soli gli
   errori di compilazione fino a build verde. Mai dichiarare "funziona" se la
   CI non è verde: riportare l'esito reale con il link al run.
2. Non si può vedere l'interfaccia: nelle scelte grafiche ambigue usare il
   comportamento standard e dire all'utente cosa verificare sul telefono.
3. Commit piccoli e descrittivi. Mai segreti. Mai toccare impostazioni repo o
   secrets: indicare all'utente cosa configurare.
4. I test del package si possono eseguire in locale con Docker:
   `docker run --rm -v "$PWD":/src -w /src swift:6.0-noble swift test --package-path packages/AlarmCore`
   (e `packages/InstaCore`)
   (avviare `dockerd` se non è attivo). L'app SwiftUI si compila solo in CI.
