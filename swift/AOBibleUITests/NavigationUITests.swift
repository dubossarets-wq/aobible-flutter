import XCTest

/// Переключение глав, свайпы, прокрутка после окон, режим «Страницы», «История», «Режим чтения» в «Ещё».
/// Место берётся из шапки («Быт 3:12»); каждый шаг проверяется, снимки — во вложениях теста
final class NavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeSeen", "YES"] + extra
        app.launch()
        XCTAssertTrue(head(app).waitForExistence(timeout: 420), "читалка не появилась")
        sleep(3)
        return app
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Кнопка места в шапке: «Быт 3:12»
    private func head(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[^ ]+ [0-9]+:[0-9]+.*")).firstMatch
    }

    private func place(_ app: XCUIApplication) -> (book: String, chapter: Int, verse: Int) {
        let l = head(app).label
        let parts = l.split(separator: " ")
        guard parts.count >= 2 else { return ("", 0, 0) }
        let cv = parts[1].split(separator: ":")
        let v = cv.count > 1 ? Int(cv[1].prefix { $0.isNumber }) ?? 0 : 0
        return (String(parts[0]), Int(cv.first ?? "") ?? 0, v)
    }

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector, velocity: CGFloat = 900) {
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.03, thenDragTo: app.coordinate(withNormalizedOffset: to), withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: 0)
    }

    private func counter(_ app: XCUIApplication) -> (Int, Int)? {
        let e = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ / [0-9]+$")).firstMatch
        guard e.exists else { return nil }
        let p = e.label.split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return p.count == 2 ? (p[0], p[1]) : nil
    }

    /// Прокрутка срабатывает каждый раз: n протяжек вверх — стих в шапке растёт после каждой, потом обратно
    private func checkScrollEveryTime(_ app: XCUIApplication, _ tag: String) {
        var fails = 0
        let ch = place(app).chapter
        for i in 0..<3 {
            let before = place(app).verse
            drag(app, from: CGVector(dx: 0.5, dy: 0.66), to: CGVector(dx: 0.5, dy: 0.36), velocity: 600)
            sleep(1)
            let after = place(app).verse
            if after <= before { fails += 1; shot("\(tag)-no-scroll-down-\(i)") }
        }
        for i in 0..<3 {
            let before = place(app).verse
            drag(app, from: CGVector(dx: 0.5, dy: 0.36), to: CGVector(dx: 0.5, dy: 0.66), velocity: 600)
            sleep(1)
            let after = place(app).verse
            if after >= before && before > 1 { fails += 1; shot("\(tag)-no-scroll-up-\(i)") }
        }
        XCTAssertEqual(place(app).chapter, ch, "\(tag): прокрутка сменила главу")
        XCTAssertEqual(fails, 0, "\(tag): прокрутка не сработала \(fails) раз из 6")
    }

    // MARK: - Прокрутка

    func test1ChapterButtonsAndSwipes() throws {
        let app = launch(["-readingStyle", "scroll"])
        let c0 = place(app).chapter
        shot("n01-start")
        app.buttons["Следующая глава"].firstMatch.tap()
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0 + 1, "кнопка «Следующая глава»")
        app.buttons["Предыдущая глава"].firstMatch.tap()
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0, "кнопка «Предыдущая глава»")
        shot("n02-after-buttons")

        // свайп влево — следующая глава, вправо — предыдущая
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5), velocity: 1500)
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0 + 1, "свайп влево")
        shot("n03-swipe-left")
        drag(app, from: CGVector(dx: 0.15, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.5), velocity: 1500)
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0, "свайп вправо")
        shot("n04-swipe-right")

        // короткий или косой жест главу не меняет
        drag(app, from: CGVector(dx: 0.55, dy: 0.5), to: CGVector(dx: 0.45, dy: 0.5), velocity: 600)
        sleep(1)
        drag(app, from: CGVector(dx: 0.7, dy: 0.65), to: CGVector(dx: 0.45, dy: 0.35), velocity: 900)
        sleep(1)
        XCTAssertEqual(place(app).chapter, c0, "глава сменилась от короткого или косого жеста")
        XCTAssertFalse(app.buttons["Готово"].firstMatch.exists, "короткий жест открыл окно слова")
        if app.buttons["Готово"].firstMatch.exists { shot("n04b-word-sheet-from-drag"); app.buttons["Готово"].firstMatch.tap(); sleep(1) }

        // прокрутка вверх-вниз работает каждый раз и главу не меняет
        app.buttons["Следующая глава"].firstMatch.tap()
        sleep(2)
        let c1 = place(app).chapter
        checkScrollEveryTime(app, "n05")
        XCTAssertEqual(place(app).chapter, c1, "прокрутка сменила главу")
        // свайпы подряд, быстро
        for _ in 0..<3 {
            drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5), velocity: 2000)
            sleep(1)
        }
        XCTAssertEqual(place(app).chapter, c1 + 3, "три свайпа подряд")
        for _ in 0..<3 {
            drag(app, from: CGVector(dx: 0.15, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.5), velocity: 2000)
            sleep(1)
        }
        XCTAssertEqual(place(app).chapter, c1, "три свайпа назад")
        shot("n06-end")
    }

    func test2ScrollAfterSheets() throws {
        let app = launch(["-readingStyle", "scroll"])
        checkScrollEveryTime(app, "s01-before")

        // окно слова (как карта: «Название · Карта» открывается из него) — закрыли, прокрутка работает каждый раз
        for round in 0..<2 {
            let tv = app.textViews.allElementsBoundByIndex.first { $0.frame.minY > 160 && $0.frame.maxY < 600 && $0.frame.height > 30 }
            let text = try XCTUnwrap(tv, "нет видимого стиха")
            text.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
            let done = app.buttons["Готово"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 5), "окно слова не открылось")
            shot("s02-word-sheet-\(round)")
            done.tap()
            sleep(2)
            checkScrollEveryTime(app, "s03-after-word-\(round)")
        }

        // «Картинка со стихом» из меню выделенного стиха
        let tv = app.textViews.allElementsBoundByIndex.first { $0.frame.minY > 160 && $0.frame.maxY < 600 && $0.frame.height > 30 }
        let text = try XCTUnwrap(tv, "нет видимого стиха")
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).press(forDuration: 0.4)
        sleep(1)
        let tabMore = app.tabBars.buttons["Ещё"].firstMatch
        let more = app.buttons.matching(NSPredicate(format: "label == 'Ещё'")).allElementsBoundByIndex.first { !tabMore.exists || $0.frame != tabMore.frame }
        let menu = try XCTUnwrap(more, "нет меню выделения")
        menu.tap()
        let image = app.buttons["Картинка со стихом"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 3), "нет пункта «Картинка со стихом»")
        image.tap()
        let close = app.buttons["Закрыть"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "окно картинки не открылось")
        sleep(1)
        shot("s04-image-sheet")
        close.tap()
        sleep(2)
        // снять выделение касанием по тексту
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        if app.buttons["Готово"].firstMatch.exists { app.buttons["Готово"].firstMatch.tap(); sleep(1) }
        checkScrollEveryTime(app, "s05-after-image")
        // и свайп главы после окон
        let c = place(app).chapter
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5), velocity: 1500)
        sleep(2)
        XCTAssertEqual(place(app).chapter, c + 1, "свайп главы после окон")
        shot("s06-end")
    }

    // MARK: - Страницы

    func test3Pages() throws {
        let app = launch(["-readingStyle", "pages"])
        let c0 = place(app).chapter
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        shot("p01-start")
        let first = try XCTUnwrap(counter(app), "нет номера страницы")
        // нажатия справа: страницы по одной, потом сразу следующая глава (без пустого листа)
        var lastPage = first.0
        var reached = false
        for i in 0..<60 {
            right.tap()
            sleep(1)
            XCTAssertFalse(app.staticTexts["Следующая глава"].exists || app.staticTexts["Предыдущая глава"].exists, "пустой лист перехода (шаг \(i))")
            if place(app).chapter == c0 + 1 { reached = true; break }
            if let c = counter(app) {
                XCTAssertEqual(c.0, lastPage + 1, "страница не перелистнулась на одну (шаг \(i))")
                lastPage = c.0
            }
        }
        XCTAssertTrue(reached, "следующая глава не открылась")
        shot("p02-next-chapter")
        sleep(1)
        XCTAssertEqual(counter(app)?.0, 1, "следующая глава открылась не с первой страницы")
        // назад — предыдущая глава с последней страницы
        left.tap()
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0, "назад в предыдущую главу")
        if let c = counter(app) { XCTAssertEqual(c.0, c.1, "предыдущая глава открылась не с последней страницы") }
        shot("p03-back-to-last-page")
        // жесты: влево — следующая страница (здесь — следующая глава), вправо — назад
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5), velocity: 1200)
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0 + 1, "свайп за последнюю страницу")
        XCTAssertEqual(counter(app)?.0, 1)
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5), velocity: 1200)
        sleep(2)
        XCTAssertEqual(counter(app)?.0, 2, "свайп влево не перелистнул страницу")
        drag(app, from: CGVector(dx: 0.15, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.5), velocity: 1200)
        sleep(2)
        XCTAssertEqual(counter(app)?.0, 1, "свайп вправо не вернул страницу")
        drag(app, from: CGVector(dx: 0.15, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.5), velocity: 1200)
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0, "свайп перед первой страницей")
        shot("p04-swipes")
        // кнопки глав внизу
        app.buttons["Следующая глава"].firstMatch.tap()
        sleep(2)
        XCTAssertEqual(place(app).chapter, c0 + 1, "кнопка «Следующая глава» в страницах")
        XCTAssertEqual(counter(app)?.0, 1)
        // нажатие на слово в середине — окно слова
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.42)).tap()
        let done = app.buttons["Готово"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 4), "нажатие на слово в «Страницах» не открыло окно")
        if done.exists {
            shot("p05-word")
            done.tap()
            sleep(1)
            right.tap()
            sleep(1)
            XCTAssertEqual(counter(app)?.0, 2, "после окна слова страница не листается")
        } else {
            shot("p05-no-word-sheet")
        }
    }

    // MARK: - «Ещё»

    func test4History() throws {
        let app = launch(["-readingStyle", "scroll"])
        app.buttons["Следующая глава"].firstMatch.tap()
        sleep(2)
        app.buttons["Следующая глава"].firstMatch.tap()
        sleep(2)
        let here = place(app)
        app.tabBars.buttons["Ещё"].firstMatch.tap()
        let history = app.buttons.matching(NSPredicate(format: "label CONTAINS 'История'")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5), "нет «Истории» в «Ещё»")
        history.tap()
        sleep(2)
        shot("h01-history")
        let rows = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".* [0-9]+:[0-9]+.*"))
        XCTAssertGreaterThan(rows.count, 1, "в истории нет записей")
        XCTAssertTrue(app.staticTexts["Сегодня"].exists, "нет заголовка «Сегодня»")
        app.buttons["День"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.datePickers.firstMatch.exists, "в «День» нет выбора даты")
        shot("h02-day")
        app.buttons["Месяц"].firstMatch.tap()
        sleep(1)
        shot("h03-month")
        app.buttons["Всё"].firstMatch.tap()
        sleep(1)
        // самая свежая запись — текущее место; нажатие открывает его в «Библии»
        let top = rows.firstMatch
        XCTAssertTrue(top.label.contains("\(here.chapter):"), "сверху не текущее место: \(top.label)")
        // открыть предыдущую запись
        let second = rows.element(boundBy: 1)
        let want = second.label
        second.tap()
        sleep(2)
        XCTAssertTrue(head(app).exists, "не вернулись в чтение")
        if let ch = want.split(separator: " ").compactMap({ $0.split(separator: ":").first.flatMap { Int($0) } }).first {
            XCTAssertEqual(place(app).chapter, ch, "открылось не то место: \(want)")
        }
        shot("h04-opened")
    }

    func test5ReadingModeInMore() throws {
        let app = launch([])
        app.tabBars.buttons["Ещё"].firstMatch.tap()
        let mode = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Режим чтения'")).firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "нет «Режим чтения» в «Ещё»")
        shot("m01-more")
        mode.tap()
        let pages = app.buttons["Страницы"].firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 3), "нет выбора «Страницы»")
        pages.tap()
        sleep(1)
        app.tabBars.buttons["Библия"].firstMatch.tap()
        sleep(3)
        XCTAssertNotNil(counter(app), "режим «Страницы» не включился")
        shot("m02-pages")
        app.tabBars.buttons["Ещё"].firstMatch.tap()
        sleep(1)
        mode.tap()
        let scroll = app.buttons["Прокрутка"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 3))
        scroll.tap()
        sleep(1)
        app.tabBars.buttons["Библия"].firstMatch.tap()
        sleep(3)
        XCTAssertNil(counter(app), "режим «Прокрутка» не включился")
        checkScrollEveryTime(app, "m03-scroll")
    }
}
