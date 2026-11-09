import XCTest

/// Настоящие касания на симуляторе: приложение пишет журнал синхронной прокрутки (Documents/sync-trace.csv) при -debugSync YES
final class SyncScrollUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeSeen", "YES", "-debugSync", "YES"] + extra
        app.launch()
        // две панели появляются, когда стартовые модули установлены
        XCTAssertTrue(app.buttons["Закрыть панель"].firstMatch.waitForExistence(timeout: 320), "нет второй панели")
        sleep(3)
        return app
    }

    private func drag(_ app: XCUIApplication, _ fromY: CGFloat, _ toY: CGFloat, _ velocity: CGFloat, hold: TimeInterval) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        a.press(forDuration: 0.02, thenDragTo: b, withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: hold)
    }

    func test1SyncScroll() throws {
        let app = launch()
        // верхняя панель ведёт: медленно, как при чтении
        for _ in 0..<8 {
            drag(app, 0.40, 0.18, 220, hold: 0.25)
            usleep(250_000)
        }
        // бросок с инерцией
        for _ in 0..<3 {
            drag(app, 0.40, 0.18, 2500, hold: 0)
            sleep(3)
        }
        // обратно вверх
        for _ in 0..<5 {
            drag(app, 0.18, 0.40, 500, hold: 0.1)
            usleep(250_000)
        }
        // нижняя панель стала ведущей
        for _ in 0..<5 {
            drag(app, 0.76, 0.58, 300, hold: 0.2)
            usleep(250_000)
        }
        drag(app, 0.76, 0.58, 2500, hold: 0)
        sleep(3)
        // снова верхняя — и до конца главы
        for _ in 0..<14 {
            drag(app, 0.40, 0.18, 1800, hold: 0)
            sleep(2)
        }
        // и от конца к началу
        for _ in 0..<16 {
            drag(app, 0.18, 0.40, 1800, hold: 0)
            sleep(2)
        }
    }

    func test3ContinuousText() throws {
        let app = launch(["-continuousVerses", "YES"])
        for _ in 0..<6 {
            drag(app, 0.40, 0.18, 300, hold: 0.2)
            usleep(250_000)
        }
        for _ in 0..<4 {
            drag(app, 0.40, 0.18, 2500, hold: 0)
            sleep(3)
        }
        for _ in 0..<5 {
            drag(app, 0.18, 0.40, 2500, hold: 0)
            sleep(3)
        }
    }

    func test2LongPressKeepsSelection() throws {
        let app = launch()
        // долгое нажатие на слове: стих выделен и остаётся выделенным после отпускания
        // при нескольких панелях построены все стихи главы — берём тот, что виден в верхней панели
        let visible = app.textViews.allElementsBoundByIndex.first { $0.frame.minY > 130 && $0.frame.maxY < 400 && $0.frame.height > 30 }
        let text = try XCTUnwrap(visible, "нет видимого стиха")
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25)).press(forDuration: 0.32)
        XCTAssertTrue(app.staticTexts["Подстрочник"].firstMatch.waitForExistence(timeout: 3), "панель выделения не появилась")
        sleep(1)
        XCTAssertTrue(app.staticTexts["Подстрочник"].firstMatch.exists, "выделение пропало после отпускания")
    }
}
