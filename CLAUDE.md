# CLAUDE.md

## Obiettivo

Versione macOS nativa di [FLIP](https://github.com/thetinyfoundry/FLIP) per uso personale.

Nessuna distribuzione: niente notarizzazione, niente Mac App Store, niente installer. L'app viene compilata ed eseguita localmente.

## Stack

- Swift, con SwiftUI per l'interfaccia e AppKit dove serve (menu bar, overlay, eventi globali).
- Compilazione con Xcode.

### Comandi

Progetto: `FlipMac/FlipMac.xcodeproj`, target e schema `FlipMac`. Eseguire i comandi dalla radice del repository.

Build (verificata con Xcode 27.2, termina con `** BUILD SUCCEEDED **`):

```sh
xcodebuild -project FlipMac/FlipMac.xcodeproj -scheme FlipMac -configuration Debug -destination 'platform=macOS' build
```

L'app compilata si trova in `~/Library/Developer/Xcode/DerivedData/FlipMac-*/Build/Products/Debug/FlipMac.app`.

Test: **non ancora disponibili.** Lo schema `FlipMac` non ha un target di test, e il comando seguente oggi fallisce con `Scheme FlipMac is not currently configured for the test action.` (codice di uscita 66). Diventerà il comando di test quando esisterà un target di test collegato allo schema:

```sh
xcodebuild -project FlipMac/FlipMac.xcodeproj -scheme FlipMac -configuration Debug -destination 'platform=macOS' test
```

Test di `FlipCore` (pacchetto Swift locale in `FlipCore/`, non ancora collegato all'app; verificati con Swift 6.4.2, 20 test superati):

```sh
swift test --package-path FlipCore
```

Avvio (dopo la build; chiudere prima eventuali istanze già aperte, per esempio quelle avviate da Xcode, altrimenti `open` riporta in primo piano quella vecchia):

```sh
open "$(xcodebuild -project FlipMac/FlipMac.xcodeproj -scheme FlipMac -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/FlipMac.app"
```

L'app vive solo nella menu bar (`LSUIElement`), senza finestra né icona nel Dock. Si chiude dal suo menu con "Esci da FlipMac".

Log: `~/Library/Logs/FlipMac/flipmac.log` (righe aggiunte in coda, mai sovrascritto).

### Permessi

- L'App Sandbox è disattivata nel target `FlipMac`: l'hook globale non funziona in sandbox.
- **Input Monitoring** (Privacy e sicurezza › Monitoraggio dell'input): necessario per il `CGEventTap` in sola osservazione che vede mouse e tastiera. Senza, il listener non parte.
- **Accessibilità** (Privacy e sicurezza › Accessibilità): richiesto già ora, servirà quando la ruota dovrà intercettare Freccia giù.
- L'app è firmata ad-hoc ("Sign to Run Locally"). Dopo una nuova build macOS può non riconoscere più i permessi concessi alla build precedente, anche se l'interruttore risulta ancora attivo: in quel caso rimuovere FlipMac dagli elenchi con "−", riaggiungerla o concedere di nuovo il permesso, poi riavviare l'app.
- Dopo aver concesso Input Monitoring può servire uscire e riaprire l'app perché il listener parta.

## Perimetro della prima versione

Incluso:

- App nella menu bar.
- Ruota di selezione attivata con **Freccia giù** durante il trascinamento di file dal Finder.
- Conversioni:
  - **Immagini**: PNG, JPEG, HEIC, WebP, TIFF.
  - **PDF**: pagine in PNG, estrazione del testo.
  - **Dati**: CSV, JSON, YAML, XML.
  - **ZIP**.

Escluso dalla prima versione:

- LibreOffice
- Motore 3D
- Tobii
- Whisper
- Menu contestuale

## Regole di lavoro

- **Licenza**: il repository FLIP originale è GPL-3.0. Non copiare né tradurre codice da lì. Usarlo solo come riferimento per il comportamento.
- **Test manuali**: le funzioni che toccano il sistema (hook globale, overlay, permessi) vanno verificate con test manuali sul Mac.
- **Output**: i file convertiti vanno salvati accanto all'originale, senza mai sovrascrivere file esistenti.
- **Git**: non fare commit né push finché non viene chiesto esplicitamente.
