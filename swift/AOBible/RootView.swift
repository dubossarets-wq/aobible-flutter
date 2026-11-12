import SwiftUI

/// Вкладки нижнего меню. Поиск — системная вкладка iOS 26: круглая кнопка справа, которая раскрывается в поле поиска
/// (всё — от самой системы: стекло, клавиатура, сворачивание меню).
enum AppTab: Hashable {
    case plans, bible, saved, more, search
}

/// Нижнее меню уходит вниз целиком вместе с верхним (когда в чтении прокрутка вниз)
struct TabBarHider: ViewModifier {
    @ObservedObject var chrome: ChromeState
    let primary: UUID?
    let active: Bool

    func body(content: Content) -> some View {
        let hidden = active && (primary.flatMap { chrome.hidden[$0] } ?? false)
        content
            .background(TabBarSlider(hidden: hidden))
    }
}

/// Нижнее меню физически уезжает вниз за край экрана и выезжает обратно (системное скрытие только растворяет его)
struct TabBarSlider: UIViewRepresentable {
    let hidden: Bool

    func makeUIView(context: Context) -> Finder { Finder() }

    func updateUIView(_ v: Finder, context: Context) { v.apply(hidden) }

    final class Finder: UIView {
        private var shown = false   // меню сейчас уехало

        private func tabBar() -> UITabBar? {
            var r: UIResponder? = self
            while let cur = r {
                if let tbc = cur as? UITabBarController { return tbc.tabBar }
                r = cur.next
            }
            return nil
        }

        func apply(_ hide: Bool) {
            #if DEBUG
            SyncTrace.write("T,apply,\(hide),shown=\(shown),found=\(tabBar() != nil)")
            #endif
            guard hide != shown, let tb = tabBar() else { return }
            shown = hide
            #if DEBUG
            SyncTrace.write("T,go,\(hide),frame=\(tb.frame),super=\(String(describing: type(of: tb.superview))),tr=\(tb.transform)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                SyncTrace.write("T,after,\(hide),frame=\(tb.frame),tr=\(tb.transform),alpha=\(tb.alpha),hidden=\(tb.isHidden)")
            }
            #endif
            // сдвигаем не саму панель (система при каждой раскладке возвращает ей место), а её содержимое
            let layer = tb.layer
            let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
            let to = hide ? CATransform3DMakeTranslation(0, 140, 0) : CATransform3DIdentity
            layer.sublayerTransform = to
            let anim = CABasicAnimation(keyPath: "sublayerTransform")
            anim.fromValue = NSValue(caTransform3D: from)
            anim.toValue = NSValue(caTransform3D: to)
            anim.duration = 0.5
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(anim, forKey: "aobSlide")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // ушли со вкладки — меню на месте
            if window == nil, shown, let tb = tabBar() {
                shown = false
                tb.layer.sublayerTransform = CATransform3DIdentity
            }
        }
    }
}

struct RootView: View {
    // начальная вкладка (для проверки на симуляторе: -debugTab more|plans|saved|bible)
    @State private var tab: AppTab = Self.startTab()
    @State private var lastTab: AppTab = Self.startTab()
    @State private var query = ""
    @State private var showSearch = false
    @AppStorage("theme") private var theme = "system"
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var plans: PlansStore
    @EnvironmentObject private var sermons: SermonStore
    @State private var debugView: String? = UserDefaults.standard.string(forKey: "debugView")
    @AppStorage("welcomeSeen") private var welcomeSeen = false
    @AppStorage("lastBuild") private var lastBuild = ""
    @AppStorage("interfaceLanguage") private var lang = "ru"
    @AppStorage("hideOnScroll") private var hideOnScroll = true

    /// Тема приложения: «как в системе» — без принуждения; тёмные темы Flutter-версии (dark, ocean, black) — тёмная
    private var scheme: ColorScheme? {
        AppThemes.scheme(theme)
    }

    @ViewBuilder
    private var debugContent: some View {
        switch debugView {
        case "appearance": AppearanceView()
        case "settings": SettingsView()
        case "mydata": MyDataView()
        case "about": AboutView()
        case "news": NewsView()
        case "help": HelpView()
        case "library": ModulesList(selected: panes.primaryBinding()).navigationTitle("Библиотека")
        case "dictionary": DictionaryView()
        case "maps": MapsView()
        case "audio": AudioSettingsView()
        case "sermons": SermonsView()
        default: EmptyView()
        }
    }

    private static func startTab() -> AppTab {
        switch UserDefaults.standard.string(forKey: "debugTab") {
        case "more": return .more
        case "plans": return .plans
        case "saved": return .saved
        default: return .bible
        }
    }

    /// Открыть место в чтении
    private func open(_ book: String, _ chapter: Int, _ verse: Int) {
        panes.open(book, chapter, verse)
        showSearch = false
        tab = .bible
        lastTab = .bible
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Планы", systemImage: "calendar", value: AppTab.plans) {
                PlansView()
            }
            Tab("Библия", systemImage: "book", value: AppTab.bible) {
                // уход нижнего меню задаётся изнутри вкладки — так его понимает система
                ReaderView()
                    .modifier(TabBarHider(chrome: panes.chrome, primary: panes.panes.first?.id, active: hideOnScroll && tab == .bible))
            }
            Tab("Закладки", systemImage: "heart", value: AppTab.saved) {
                BookmarksView()
            }
            Tab("Ещё", systemImage: "line.3.horizontal", value: AppTab.more) {
                MoreView()
            }
            Tab(value: AppTab.search, role: .search) {
                Color.clear
            }
        }
        // при прокрутке вниз нижнее меню (вместе с поиском) уходит вниз целиком, как и верхнее, при прокрутке вверх — возвращается
        .tabBarMinimizeBehavior(.never)
        // мини-проигрыватель над нижним меню, пока идёт аудио
        .modifier(AudioAccessory(active: audio.active))
        // проверка на симуляторе: -debugView appearance|settings|mydata|about|news|help|library|dictionary|maps|audio|sermons
        .sheet(isPresented: Binding(get: { debugView != nil }, set: { if !$0 { debugView = nil } })) {
            NavigationStack { debugContent }
        }
        .onAppear {
            if let q = UserDefaults.standard.string(forKey: "debugSearch") {
                query = q
                showSearch = true
            }
        }
        .sheet(isPresented: Binding(get: { !welcomeSeen }, set: { if !$0 { welcomeSeen = true } })) {
            WelcomeSheet()
        }
        .task {
            // перед обновлением приложения — копия данных (последние 5)
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            if !lastBuild.isEmpty, lastBuild != build {
                UserData.snapshot("до обновления с версии \(lastBuild)", marks: marks, plans: plans, sermons: sermons)
            }
            lastBuild = build
            // данные Flutter-версии (если приложение стоит поверх неё): настройки и язык — один раз
            let ud = UserDefaults.standard
            if !ud.bool(forKey: "flutterImported") {
                if let s = ud.string(forKey: "flutter.settings") { UserData.applySettings(s) }
                if let l = ud.string(forKey: "flutter.lang"), interfaceLanguages.contains(where: { $0.0 == l }) { lang = l }
                ud.set(true, forKey: "flutterImported")
            }
            Reminders.schedule(plans.plans)
            // первый запуск: основной перевод, затем остальное в фоне
            await Starter.run(store: store, lang: lang)
        }
        // кнопка поиска в меню — вход: страница поиска открывается поверх меню со своей нижней панелью
        // (слева всегда «назад», рядом системное поле поиска), а выбранной остаётся прежняя вкладка
        .onChange(of: tab) { _, new in
            if new == .search {
                tab = lastTab
                // страница поиска появляется сразу, без анимации выезда — как системная вкладка, и клавиатура
                // не ждёт окончания анимации
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { showSearch = true }
            } else {
                lastTab = new
            }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchPage(query: $query, onClose: { showSearch = false }, onOpen: open)
                .preferredColorScheme(scheme)
        }
        .environment(\.openVerse, OpenVerse(run: open))
        .environment(\.readerPalette, AppThemes.palette(theme))
        .environment(\.locale, Locale(identifier: lang == "zh" ? "zh-Hans" : lang))
        .tint(theme == "system" ? nil : AppThemes.palette(theme).accent)
        .preferredColorScheme(scheme)
    }
}

/// Мини-проигрыватель над нижним меню: на iOS 26.1 и новее — только пока идёт аудио
private struct AudioAccessory: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: active) { AudioBar() }
        } else {
            content.tabViewBottomAccessory { AudioBar() }
        }
    }
}
