import XCTest

/// Test di interfaccia del CRUD: premono davvero i pulsanti nel simulatore (dati di esempio in memoria).
final class CRUDUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debugScreen", screen]
        app.launch()
        return app
    }

    private func cell(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: text).firstMatch
    }

    /// Aspetta che l'elemento sparisca (anche dopo un'animazione di uscita).
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func search(_ app: XCUIApplication, _ text: String) {
        let field = app.searchFields.firstMatch
        // In una schermata aperta da un'altra la barra di ricerca compare trascinando verso il basso.
        if !field.waitForExistence(timeout: 3) { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    /// Testi della riga "Serie completate" nel dettaglio di un allenamento.
    private func completedSetsRow(_ app: XCUIApplication) -> String {
        let row = app.cells.containing(.staticText, identifier: "Serie completate").firstMatch
        return row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "|")
    }

    /// Attende (senza pause fisse) che la riga "Serie completate" mostri il conteggio atteso.
    private func waitForCompletedSets(_ app: XCUIApplication, count: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if completedSetsRow(app).hasSuffix(", \(count)") { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    // MARK: - Schede

    func testDeleteTemplateFromVisibleRowMenu() {
        let app = launch("templates")
        XCTAssertTrue(app.staticTexts["Push"].waitForExistence(timeout: 10))
        app.buttons["Azioni scheda Push"].tap()
        app.buttons["Elimina"].tap()
        let confirm = app.buttons["Elimina \"Push\""]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "serve la conferma")
        XCTAssertTrue(app.staticTexts["Push"].exists, "prima della conferma la scheda c'è ancora")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Gambe"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Push"].exists)
        // Lo storico resta.
        app.tabBars.buttons["Storico"].tap()
        XCTAssertTrue(app.staticTexts["Push"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.cells.count, 2)
    }

    func testDeleteTemplateBySwipeWithOpenSession() {
        let app = launch("home-open")
        XCTAssertTrue(app.staticTexts["Allenamento in corso"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Schede"].tap()
        cell(app, "Push").swipeLeft()
        app.buttons["Elimina"].tap()
        app.buttons["Elimina \"Push\""].tap()
        XCTAssertTrue(app.staticTexts["Gambe"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Push"].exists)
        // La sessione aperta continua.
        app.tabBars.buttons["Allenamento"].tap()
        XCTAssertTrue(app.staticTexts["Allenamento in corso"].waitForExistence(timeout: 3))
    }

    func testDeleteTemplateFromEditor() {
        let app = launch("templates")
        app.staticTexts["Push"].tap()
        XCTAssertTrue(app.buttons["Altre azioni"].waitForExistence(timeout: 5))
        app.buttons["Altre azioni"].tap()
        app.buttons["Elimina scheda"].tap()
        let confirm = app.buttons["Elimina \"Push\""]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        // Si torna alla lista, senza la scheda; l'app non si chiude.
        XCTAssertTrue(app.staticTexts["Gambe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Push"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        app.tabBars.buttons["Storico"].tap()
        XCTAssertEqual(app.cells.count, 2, "lo storico non cambia")
    }

    func testRemoveExerciseFromTemplateAsksConfirmation() {
        let app = launch("template-editor")
        let name = "Panca piana con bilanciere"
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
        app.buttons["Azioni esercizio \(name)"].tap()
        app.buttons["Rimuovi dalla scheda"].tap()
        let confirm = app.buttons["Rimuovi \"\(name)\""]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Military press"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    // MARK: - Catalogo

    func testDeleteUnusedExercise() {
        let app = launch("catalog")
        search(app, "Affondi")
        let row = cell(app, "Affondi con manubri")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Elimina"].tap()
        let confirm = app.buttons["Elimina"].firstMatch
        XCTAssertTrue(app.staticTexts["Eliminare \"Affondi con manubri\"?"].waitForExistence(timeout: 3) || confirm.exists)
        app.buttons.matching(NSPredicate(format: "label == 'Elimina'")).element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts["Affondi con manubri"].waitForExistence(timeout: 2))
    }

    func testExerciseInHistoryCannotBeDeletedButCanBeArchived() {
        let app = launch("catalog")
        search(app, "Panca piana")
        let row = cell(app, "Panca piana con bilanciere")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Elimina"].tap()
        let alert = app.alerts["Non si può eliminare"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts.element(boundBy: 1).label.contains("compare in 2 allenamenti"))
        alert.buttons["Archivia"].tap()
        XCTAssertFalse(app.staticTexts["Panca piana con bilanciere"].waitForExistence(timeout: 2), "archiviato: sparisce dal catalogo")
    }

    func testExerciseOnlyInTemplatesShowsWhichAndAsksConfirmation() {
        let app = launch("templates")
        XCTAssertTrue(app.buttons["Azioni scheda Gambe"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Impostazioni"].tap()
        let catalogLink = app.buttons["Catalogo esercizi"]
        for _ in 0..<6 where !catalogLink.isHittable { app.swipeUp() }
        catalogLink.tap()
        let confirm = app.buttons["Rimuovi dalle schede ed elimina"]

        // Una sola scheda ("Gambe"): la frase la nomina al singolare; confermando l'esercizio sparisce.
        search(app, "Squat con")
        let squat = cell(app, "Squat con bilanciere")
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        squat.swipeLeft()
        app.buttons["Elimina"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["È usato nella scheda: Gambe. Se continui verrà tolto da questa scheda e poi eliminato."].exists)
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["Squat con bilanciere"]))

        // Più schede: duplico "Gambe" (ora contiene "Leg press"); la frase elenca entrambe al plurale.
        // Prima chiudo la tastiera della ricerca, che copre la barra delle schede.
        app.searchFields.firstMatch.typeText("\n")
        XCTAssertTrue(app.tabBars.buttons["Schede"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Schede"].tap()
        XCTAssertTrue(app.buttons["Azioni scheda Gambe"].waitForExistence(timeout: 5))
        app.buttons["Azioni scheda Gambe"].tap()
        app.buttons["Duplica"].tap()
        XCTAssertTrue(app.staticTexts["Gambe (copia)"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Impostazioni"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Leg press")
        let legPress = cell(app, "Leg press")
        XCTAssertTrue(legPress.waitForExistence(timeout: 5))
        legPress.swipeLeft()
        app.buttons["Elimina"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["È usato nelle schede: Gambe, Gambe (copia). Se continui verrà tolto da queste schede e poi eliminato."].exists)
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["Leg press"]))
    }

    func testEditSheetHasVisibleArchiveAndDelete() {
        let app = launch("exercise-edit")
        XCTAssertTrue(app.buttons["Archivia esercizio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Elimina esercizio"].exists)
    }

    // MARK: - Storico

    func testEditHistorySession() {
        let app = launch("history")
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Serie completate"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCompletedSets(app, count: 10), completedSetsRow(app))

        // Rinomina
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nome'")).firstMatch.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Spinta")
        app.alerts.buttons["Salva"].tap()
        XCTAssertTrue(app.navigationBars["Spinta"].waitForExistence(timeout: 3))

        // Aggiungi una serie al primo esercizio
        app.buttons["Aggiungi serie"].firstMatch.tap()
        XCTAssertTrue(waitForCompletedSets(app, count: 11), completedSetsRow(app))

        // Elimina una serie dal foglio di correzione, con conferma
        app.buttons.matching(NSPredicate(format: "label CONTAINS '×'")).firstMatch.tap()
        let deleteSet = app.buttons["Elimina serie"]
        XCTAssertTrue(deleteSet.waitForExistence(timeout: 3))
        deleteSet.tap()
        let confirm = app.buttons["Elimina serie"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(waitForCompletedSets(app, count: 10), completedSetsRow(app))
    }

    func testDeleteWholeHistorySession() {
        let app = launch("history")
        app.cells.firstMatch.tap()
        let delete = app.buttons["Elimina allenamento"]
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["Elimina"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Storico"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.cells.count, 1)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testCreatePastSession() {
        let app = launch("history")
        XCTAssertTrue(app.buttons["Aggiungi allenamento"].waitForExistence(timeout: 5))
        app.buttons["Aggiungi allenamento"].tap()
        let save = app.buttons["Salva"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertFalse(save.isEnabled, "serve almeno un esercizio")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Esercizio'")).firstMatch.tap()
        app.staticTexts["Affondi con manubri"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["Storico"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.cells.count, 3)
    }

    // MARK: - Allenamento in corso, impostazioni

    func testActiveSessionRenameAndDiscardWithCompletedSets() {
        let app = launch("home-open")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Allenamento in corso'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Altre azioni"].waitForExistence(timeout: 5))
        app.buttons["Altre azioni"].tap()
        app.buttons["Rinomina allenamento"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Test")
        app.alerts.buttons["Salva"].tap()
        XCTAssertTrue(app.navigationBars["Test"].waitForExistence(timeout: 3))

        // Una serie è già completata: scartare deve comunque essere possibile, con conferma.
        app.buttons["Altre azioni"].tap()
        app.buttons["Scarta allenamento"].tap()
        let confirm = app.buttons["Scarta allenamento"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Da una scheda"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Allenamento in corso"].exists)
    }

    func testSettingsReset() {
        let app = launch("settings")
        XCTAssertTrue(app.buttons["Ripristina valori predefiniti"].waitForExistence(timeout: 5))
        app.buttons["Ripristina valori predefiniti"].tap()
        XCTAssertTrue(app.buttons["Ripristina"].waitForExistence(timeout: 3))
    }
}
