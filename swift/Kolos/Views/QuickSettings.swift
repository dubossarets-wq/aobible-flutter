import SwiftUI

/// Настройка, которую можно вынести в «Ещё»: переключатель, выбор из списка, ползунок или «Читать параллельно»
struct QuickSetting: Identifiable {
    enum Kind {
        case toggle(def: Bool)
        case choice(def: String, options: [(value: String, label: String)])
        case slider(def: Double, range: ClosedRange<Double>, step: Double)
        case parallel
    }

    /// Ключ в хранилище настроек (у «Читать параллельно» — своё имя)
    let id: String
    /// Подпись (ключ перевода)
    let title: String
    let kind: Kind
}

enum QuickSettings {
    /// Вынесенные настройки — идентификаторы через запятую, в порядке добавления
    static let key = "quickSettings"

    static let all: [QuickSetting] = [
        QuickSetting(id: "parallel", title: "Читать параллельно", kind: .parallel),
        QuickSetting(id: "readingStyle", title: "Режим чтения", kind: .choice(def: "scroll", options: [("scroll", "Прокрутка"), ("pages", "Страницы")])),
        QuickSetting(id: "pageVerseBreak", title: "Переносить стихи", kind: .choice(def: "line", options: [("line", "Построчно"), ("verse", "По стихам")])),
        QuickSetting(id: "panesStacked", title: "Панели друг над другом", kind: .toggle(def: true)),
        QuickSetting(id: "syncScroll", title: "Синхронная прокрутка", kind: .toggle(def: true)),
        QuickSetting(id: "hideOnScroll", title: "Прятать меню при прокрутке", kind: .toggle(def: true)),
        QuickSetting(id: "keepScreenOn", title: "Не гасить экран при чтении", kind: .toggle(def: false)),
        QuickSetting(id: "showVerseNumbers", title: "Номера стихов", kind: .toggle(def: true)),
        QuickSetting(id: "showStrongs", title: "Номера Стронга", kind: .toggle(def: false)),
        QuickSetting(id: "showXrefs", title: "Параллельные места после стиха", kind: .toggle(def: true)),
        QuickSetting(id: "showIllustrations", title: "Иллюстрации к стихам", kind: .toggle(def: true)),
        QuickSetting(id: "theme", title: "Тема", kind: .choice(def: "system", options: AppThemes.all.map { ($0.id, $0.label) })),
        QuickSetting(id: "fontFamily", title: "Шрифт", kind: .choice(def: "system", options: ReadingFonts.all.map { ($0.id, $0.label) })),
        QuickSetting(id: "fontSize", title: "Размер текста", kind: .slider(def: 19, range: 13...40, step: 1)),
        QuickSetting(id: "fontWeight", title: "Толщина шрифта", kind: .slider(def: 400, range: 300...700, step: 100)),
        QuickSetting(id: "lineHeight", title: "Межстрочный интервал", kind: .slider(def: 1.45, range: 1.1...2.2, step: 0.05)),
        QuickSetting(id: "verseSpacing", title: "Между стихами", kind: .slider(def: 0.55, range: 0...1.6, step: 0.05)),
        QuickSetting(id: "textMargin", title: "Поля по бокам", kind: .slider(def: 14, range: 8...48, step: 2)),
        QuickSetting(id: "verseNumPos", title: "Номер стиха", kind: .choice(def: "sup", options: [("sup", "Над строкой"), ("inline", "В строке")])),
        QuickSetting(id: "showHeadings", title: "Заголовки разделов", kind: .toggle(def: true)),
        QuickSetting(id: "headingColor", title: "Цвет заголовков", kind: .choice(def: HeadingStyle.defaultColor, options: HeadingStyle.colors.map { ($0.0, $0.1) })),
        QuickSetting(id: "headingSize", title: "Размер заголовков", kind: .slider(def: HeadingStyle.defaultSize, range: 0.7...1.3, step: 0.05)),
        QuickSetting(id: "continuousVerses", title: "Сплошной текст", kind: .toggle(def: false)),
        QuickSetting(id: "commentView", title: "Комментарии в тексте", kind: .choice(def: "tag", options: [("below", "Под стихом"), ("tag", "Меткой после стиха")])),
        QuickSetting(id: "commentaryFontSize", title: "Размер комментариев", kind: .slider(def: 19, range: 14...32, step: 1)),
    ]

    static func find(_ id: String) -> QuickSetting? { all.first { $0.id == id } }

    static func ids(_ raw: String) -> [String] { raw.split(separator: ",").map(String.init) }
}

// MARK: - Вынести / убрать

/// Нажатие на настройку и проведение пальцем вправо (или долгое нажатие) выносит её в «Ещё» либо убирает оттуда
private struct PinnableModifier: ViewModifier {
    let id: String
    @AppStorage(QuickSettings.key) private var raw = ""

    private var pinned: Bool { QuickSettings.ids(raw).contains(id) }

    private func toggle() {
        var list = QuickSettings.ids(raw)
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id) }
        raw = list.joined(separator: ",")
    }

    private var button: some View {
        Button { toggle() } label: {
            Label(pinned ? "Убрать из «Ещё»" : "Вынести в «Ещё»", systemImage: pinned ? "pin.slash.fill" : "pin.fill")
        }
        .tint(.orange)
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) { button }
            .contextMenu { button }
    }
}

extension View {
    /// Настройку можно вынести в «Ещё» (проведите вправо или зажмите)
    func pinnable(_ id: String) -> some View { modifier(PinnableModifier(id: id)) }
}

// MARK: - Раздел в «Ещё»

/// «Быстрые настройки» в «Ещё»: вынесенные настройки одной строкой каждая; проведите влево — убрать
struct QuickSettingsSection: View {
    @AppStorage(QuickSettings.key) private var raw = ""

    var body: some View {
        let items = QuickSettings.ids(raw).compactMap(QuickSettings.find)
        if !items.isEmpty {
            Section {
                ForEach(items) { s in
                    QuickSettingRow(setting: s)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { unpin(s.id) } label: {
                                Label("Убрать", systemImage: "pin.slash.fill")
                            }
                        }
                }
            } header: {
                Text("Быстрые настройки")
            }
        }
    }

    private func unpin(_ id: String) {
        raw = QuickSettings.ids(raw).filter { $0 != id }.joined(separator: ",")
    }
}

private struct QuickSettingRow: View {
    let setting: QuickSetting

    var body: some View {
        switch setting.kind {
        case .toggle(let def):
            QuickToggle(setting: setting, def: def)
        case .choice(let def, let options):
            QuickChoice(setting: setting, def: def, options: options)
        case .slider(let def, let range, let step):
            QuickSlider(setting: setting, def: def, range: range, step: step)
        case .parallel:
            ParallelToggle()
        }
    }
}

private struct QuickToggle: View {
    let title: String
    @AppStorage private var on: Bool

    init(setting: QuickSetting, def: Bool) {
        title = setting.title
        _on = AppStorage(wrappedValue: def, setting.id)
    }

    var body: some View {
        Toggle(LocalizedStringKey(title), isOn: $on)
    }
}

private struct QuickChoice: View {
    @EnvironmentObject private var panes: PanesStore
    let id: String
    let title: String
    let options: [(value: String, label: String)]
    @AppStorage private var value: String

    init(setting: QuickSetting, def: String, options: [(value: String, label: String)]) {
        id = setting.id
        title = setting.title
        self.options = options
        _value = AppStorage(wrappedValue: def, setting.id)
    }

    var body: some View {
        Picker(LocalizedStringKey(title), selection: $value) {
            ForEach(options, id: \.value) { o in Text(LocalizedStringKey(o.label)).tag(o.value) }
        }
        // как в настройках: в режиме «Страницы» остаётся одно окно
        .onChange(of: value) { _, new in
            if id == "readingStyle" && new == "pages" { panes.trimToLimit() }
        }
    }
}

private struct QuickSlider: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    @AppStorage private var value: Double

    init(setting: QuickSetting, def: Double, range: ClosedRange<Double>, step: Double) {
        title = setting.title
        self.range = range
        self.step = step
        _value = AppStorage(wrappedValue: def, setting.id)
    }

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer(minLength: 8)
            Text(step >= 1 ? "\(Int(value))" : String(format: "%.2f", value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

/// «Читать параллельно»: включить — рядом откроется второе окно с тем же переводом, выключить — останется одно
struct ParallelToggle: View {
    @EnvironmentObject private var panes: PanesStore

    var body: some View {
        Toggle("Читать параллельно", isOn: Binding(
            get: { panes.panes.count > 1 },
            set: { on in
                if on {
                    if let last = panes.panes.last, panes.panes.count < panes.paneLimit {
                        panes.addPane(after: last.id, moduleId: last.moduleId)
                    }
                } else {
                    for p in panes.panes.dropFirst() { panes.closePane(p.id) }
                }
            }
        ))
        .disabled(panes.paneLimit < 2 && panes.panes.count < 2)
    }
}
