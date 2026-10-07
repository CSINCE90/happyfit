# HappyFit – convenzioni

- Linguaggio: Swift, UI con SwiftUI. Persistenza con SwiftData. Architettura MVVM.
- Commenti nel codice in italiano.
- Nessuna dipendenza esterna senza chiedere prima.
- Il progetto Xcode è generato da `project.yml`: ogni volta che aggiungi, rimuovi o sposti file esegui `xcodegen generate`.
- Build da riga di comando con `xcodebuild` (schemi `HappyFit` e `HappyFitWatch`), ad esempio:
  `xcodebuild -project HappyFit.xcodeproj -scheme HappyFit -destination 'generic/platform=iOS Simulator' build`
- Codice condiviso iPhone/Watch in `Shared/`; codice specifico nelle rispettive cartelle.
- Deployment: iOS 17.0, watchOS 10.0.
