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

Avvio: _da definire_

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
