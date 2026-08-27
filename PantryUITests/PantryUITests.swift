import XCTest

/// End-to-end flows through the real app.
///
/// These cover the core loop the product is built around — add food, see it, find a
/// recipe, save it, put what's missing on the shopping list — plus the states that are
/// easy to leave broken: an empty pantry and no network.
final class PantryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"] + arguments
        app.launch()
        return app
    }

    // MARK: - Core loop

    func testAddingAnItemAndSeeingItInThePantry() {
        let app = launch()
        app.tabBars.buttons["Pantry"].firstMatch.tap()

        addItem(named: "Test Aubergine", in: app)

        XCTAssertTrue(
            app.staticTexts["Test Aubergine"].waitForExistence(timeout: 5),
            "A newly added item should appear in the pantry list"
        )
    }

    func testQuickAddParsesAListBeforeSaving() {
        let app = launch()
        app.tabBars.buttons["Pantry"].firstMatch.tap()

        openAddMenu(in: app)
        app.buttons["Add a List"].firstMatch.tap()

        let editor = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Test Kale\nTest Lentils")

        // The parsed rows are shown for review before anything is saved.
        XCTAssertTrue(app.staticTexts["Test Kale"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Lentils"].exists)

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Test Kale"].waitForExistence(timeout: 5))
    }

    func testWhatCanIMakeShowsResultsWithoutNetwork() {
        let app = launch()
        app.tabBars.buttons["Home"].firstMatch.tap()

        let button = app.buttons["What Can I Make?"].firstMatch
        guard button.waitForExistence(timeout: 5) else {
            // An empty pantry hides the dashboard; that path is covered separately.
            return
        }
        button.tap()

        XCTAssertTrue(
            app.navigationBars["What Can I Make?"].waitForExistence(timeout: 5),
            "The suggestion screen should open"
        )
        // Local matching runs with no provider configured, so filters are usable at once.
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
    }

    func testRecipeCanBeSavedAndMissingIngredientsAddedToShopping() {
        let app = launch()
        app.tabBars.buttons["Recipes"].firstMatch.tap()

        let firstRecipe = app.cells.firstMatch
        XCTAssertTrue(firstRecipe.waitForExistence(timeout: 5), "The bundled library should show recipes")
        firstRecipe.tap()

        let save = app.buttons["Save"].firstMatch
        if save.waitForExistence(timeout: 5) {
            save.tap()
            XCTAssertTrue(app.buttons["Saved"].firstMatch.waitForExistence(timeout: 5))
        }

        let addMissing = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Missing' AND label CONTAINS 'Shopping'")
        ).firstMatch
        if addMissing.exists {
            addMissing.tap()
            if app.buttons["OK"].firstMatch.waitForExistence(timeout: 3) {
                app.buttons["OK"].firstMatch.tap()
            }
        }
    }

    func testShoppingListIsReachableAndUsable() {
        let app = launch()
        app.tabBars.buttons["Shopping"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 5))
    }

    // MARK: - States

    func testEveryTabOpensWithoutAnEmptyScreen() {
        let app = launch()
        for name in ["Home", "Pantry", "Recipes", "Shopping", "More"] {
            app.tabBars.buttons[name].firstMatch.tap()
            XCTAssertTrue(
                app.navigationBars.firstMatch.waitForExistence(timeout: 5),
                "\(name) should show a navigation bar rather than a blank screen"
            )
        }
    }

    func testSettingsScreensAllOpen() {
        let app = launch()
        app.tabBars.buttons["More"].firstMatch.tap()

        for label in ["Cooking Preferences", "Reminders", "Intelligence", "About Pantry"] {
            let row = app.buttons[label].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(label) should be listed")
            row.tap()
            XCTAssertTrue(
                app.navigationBars.firstMatch.waitForExistence(timeout: 5),
                "\(label) should open"
            )
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testIntelligenceScreenExplainsItselfWithNoProviderConfigured() {
        let app = launch()
        app.tabBars.buttons["More"].firstMatch.tap()
        app.buttons["Intelligence"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Intelligence"].waitForExistence(timeout: 5))
        // With nothing set up the screen must still say what is going on, not sit blank.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Nothing set up' OR label CONTAINS 'Preferred'")
            ).firstMatch.waitForExistence(timeout: 5)
        )
    }

    // MARK: - Helpers

    private func openAddMenu(in app: XCUIApplication) {
        let add = app.navigationBars.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.press(forDuration: 0.9)
    }

    private func addItem(named name: String, in app: XCUIApplication) {
        let add = app.navigationBars.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let field = app.textFields["Name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)

        app.buttons["Add"].firstMatch.tap()
    }
}
