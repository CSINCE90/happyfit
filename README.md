# HappyFit

App iOS + watchOS per tracciare gli allenamenti in palestra. SwiftUI + SwiftData, architettura MVVM.

## Struttura
- `Shared/` codice condiviso iPhone + Watch
- `HappyFit/` app iOS
- `HappyFitWatch/` app watchOS (companion)
- `HappyFitTests/` test

## Rigenerare il progetto
Il file `HappyFit.xcodeproj` non è versionato: si genera da `project.yml`.

```
brew install xcodegen
xcodegen generate
```

## Build da riga di comando
```
xcodebuild -project HappyFit.xcodeproj -scheme HappyFit -destination 'generic/platform=iOS Simulator' build
xcodebuild -project HappyFit.xcodeproj -scheme HappyFitWatch -destination 'generic/platform=watchOS Simulator' build
```

## Firma
Imposta `DEVELOPMENT_TEAM` in `project.yml` (riga commentata) e rigenera.
