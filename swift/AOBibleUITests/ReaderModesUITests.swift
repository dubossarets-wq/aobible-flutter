import XCTest

/// Режимы чтения на симуляторе: страницы как в книге, скрытие шапки при прокрутке, полоска прочтения. Снимки — во вложениях теста
final class ReaderModesUITests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeSeen", "YES"] + extra
        app.launch()
        let head = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Быт'")).firstMatch
        XCTAssertTrue(head.waitForExistence(timeout: 420), "читалка не появилась")
        sleep(4)
        return app
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func test1Pages() throws {
        let app = launch(["-readingStyle", "pages"])
        shot("p01-first-page")
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        right.tap()
        sleep(2)
        shot("p02-after-right-tap")
        right.tap()
        sleep(2)
        shot("p03-after-second-right-tap")
        left.tap()
        sleep(2)
        shot("p04-after-left-tap")
        // жест листания
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 600, thenHoldForDuration: 0)
        sleep(2)
        shot("p05-after-swipe")
        // нажатие в середине (слово) — открывается список словарей
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.2)).tap()
        sleep(3)
        shot("p06-word-tap")
        // дойти до конца главы и перейти в следующую
        for _ in 0..<40 {
            right.tap()
            usleep(900_000)
        }
        shot("p07-after-many-turns")
    }

    func test2HideOnScroll() throws {
        let app = launch([])
        shot("h01-top")
        for _ in 0..<4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)), withVelocity: 500, thenHoldForDuration: 0.1)
            usleep(400_000)
        }
        sleep(1)
        shot("h02-scrolled-down-chrome-hidden")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 400, thenHoldForDuration: 0.1)
        sleep(1)
        shot("h03-scrolled-up-chrome-back")
        // справа и слева от текста нажатие главы не переключает
        let head = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Быт'")).firstMatch
        let before = head.label
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        sleep(1)
        XCTAssertEqual(head.label, before, "глава переключилась нажатием у края")
        shot("h04-edge-tap-no-switch")
    }
}
