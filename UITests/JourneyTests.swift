import XCTest

final class JourneyTests: XCTestCase {
    func testListsKeepTheirOwnItemsAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["LIST_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()

        func at(_ page: String) {
            let bar = app.navigationBars[page]
            let visible = NSPredicate(format: "exists == true AND isHittable == true")
            let ready = XCTNSPredicateExpectation(predicate: visible, object: bar)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, page)
        }

        func button(_ name: String) -> XCUIElement {
            let matches = app.buttons.matching(identifier: name)
            return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
        }

        func create(_ kind: String, _ title: String) {
            button("Add \(kind)").tap()
            let alert = app.alerts["New \(kind)"]
            let field = alert.textFields["Title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            alert.buttons["Add"].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        }

        func openList(_ title: String) {
            button("list-\(title)").tap()
            at(title)
        }

        func home() {
            button("screen-menu").tap()
            button("screen-List of Lists").tap()
            at("List of Lists")
        }

        let weekend = ["Visit the farmers market", "Walk by the river"]
        let book = "The Little Prince"

        at("List of Lists")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list-'")).count, 0)
        shot("01-empty")
        create("list", "Weekend")
        create("list", "Books")
        XCTAssertTrue(button("list-Weekend").isHittable)
        XCTAssertTrue(button("list-Books").isHittable)
        shot("02-directory")

        openList("Weekend")
        for item in weekend { create("item", item) }
        for item in weekend { XCTAssertTrue(button(item).isHittable) }
        shot("03-items")
        button("screen-menu").tap()
        for page in ["List of Lists", "Weekend", "Books"] {
            XCTAssertTrue(button("screen-\(page)").isHittable)
        }
        shot("04-pages")
        button("screen-Books").tap()
        at("Books")
        for item in weekend { XCTAssertFalse(button(item).isHittable) }
        create("item", book)
        home()

        app.terminate()
        app.launch()
        at("List of Lists")
        openList("Weekend")
        for item in weekend { XCTAssertTrue(button(item).isHittable) }
        XCTAssertFalse(button(book).isHittable)
        home()
        openList("Books")
        XCTAssertTrue(button(book).isHittable)
        for item in weekend { XCTAssertFalse(button(item).isHittable) }
        home()
        shot("05-return")

        app.swipeLeft()
        at("Books")
        button(book).tap()
        let rename = app.alerts["Rename item"]
        let title = rename.textFields["Title"]
        title.tap()
        title.typeText(" (reread)")
        rename.buttons["Save"].tap()
        let renamed = button(book + " (reread)")
        XCTAssertTrue(renamed.isHittable)
        renamed.swipeLeft()
        button("Delete").tap()
        button("Delete item").tap()
        XCTAssertTrue(app.staticTexts["No items yet"].waitForExistence(timeout: 5))
        button("All lists").tap()
        at("List of Lists")
        button("list-Books").swipeLeft()
        button("Delete").tap()
        button("Delete list").tap()
        XCTAssertTrue(button("list-Books").waitForNonExistence(timeout: 5))
        openList("Weekend")
        for item in weekend { XCTAssertTrue(button(item).isHittable) }
        home()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
