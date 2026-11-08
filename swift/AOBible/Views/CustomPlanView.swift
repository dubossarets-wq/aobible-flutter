import SwiftUI

/// Свой план: «Последовательно» (раздел или свои книги за N дней) и «Параллельно» («Глав в день» / «За срок»).
/// Все функции веб- и Flutter-версий: свои книги, нагрузка «≈ N гл. в день · до даты», сроки словами,
/// первый день, запоминание выбора
struct CustomPlanView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var plans: PlansStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("interfaceLanguage") private var lang = "ru"

    @AppStorage("cp.mode") private var mode = "seq"
    @AppStorage("cp.parMode") private var parMode = "perday"
    @AppStorage("cp.scope") private var scope = "nt"
    @AppStorage("cp.days") private var days = 90
    @AppStorage("cp.periodDays") private var periodDays = 90
    @AppStorage("cp.own") private var ownRaw = ""
    @AppStorage("cp.streams") private var streamsRaw = "ot:1,ps:1,nt:1"
    @State private var cache = PlanChapterCache()
    @State private var message: String?

    private let scopes: [(id: String, label: String, icon: String, books: [String])] = [
        ("all", "Вся Библия", "book", []),
        ("ot", "Ветхий Завет", "scroll", []),
        ("nt", "Новый Завет", "text.book.closed", []),
        ("gospels", "Евангелия", "cross", ["Matt", "Mark", "Luke", "John"]),
        ("ps", "Псалтирь", "music.note", ["Ps"]),
        ("own", "Свои книги", "checklist", []),
    ]

    private let presets: [[(Int, String)]] = [
        [(7, "Неделя"), (14, "2 недели"), (30, "Месяц")],
        [(90, "3 месяца"), (180, "Полгода"), (365, "Год")],
    ]

    // MARK: данные

    private var module: InstalledModule? {
        store.module("rst-plus") ?? store.module(panes.primaryModule) ?? store.bibles.first
    }

    private var own: [String] {
        let set = Set(ownRaw.split(separator: ",").map(String.init))
        return Books.all.filter { set.contains($0.id) }.map { $0.id }
    }

    private func setOwn(_ ids: Set<String>) { ownRaw = ids.sorted().joined(separator: ",") }

    private var streams: [String: Int] {
        var d: [String: Int] = [:]
        for p in streamsRaw.split(separator: ",") {
            let a = p.split(separator: ":")
            if a.count == 2, let n = Int(a[1]) { d[String(a[0])] = min(10, max(1, n)) }
        }
        return d
    }

    private func setStreams(_ d: [String: Int]) {
        streamsRaw = PlanLogic.streams.compactMap { s in d[s.key].map { "\(s.key):\($0)" } }.joined(separator: ",")
    }

    private func chapters(_ books: [String]) -> [ChapterRef] {
        guard let m = module else { return [] }
        return books.flatMap { b -> [ChapterRef] in
            if let c = cache.d[m.id + b] { return c }
            let c = store.chapterList(module: m, books: [b])
            cache.d[m.id + b] = c
            return c
        }
    }

    private func scopeBooks(_ id: String) -> [String] {
        switch id {
        case "all": return Books.all.filter { ($0.t == "OT" || $0.t == "NT") && $0.dc != true }.map { $0.id }
        case "ot": return Books.all.filter { $0.t == "OT" && $0.dc != true }.map { $0.id }
        case "nt": return Books.all.filter { $0.t == "NT" }.map { $0.id }
        case "own": return own
        default: return scopes.first { $0.id == id }?.books ?? []
        }
    }

    private var par: Bool { mode == "par" }
    private var period: Bool { par && parMode == "period" }
    private var sel: [StreamSel] { PlanLogic.streamList(on: streams, own: own) }
    private var parBooks: [String] { sel.flatMap { $0.books } }
    private var parDays: Int { period ? 0 : PlanLogic.parallelDays(sel, chapters: chapters) }
    private var needOwn: Bool { (par ? streams["own"] != nil : scope == "own") && own.isEmpty }
    private var canStart: Bool {
        if needOwn { return false }
        if par && !period { return parDays > 0 }
        return !(par ? parBooks : scopeBooks(scope)).isEmpty
    }

    // MARK: вид

    var body: some View {
        Form {
            Section {
                Picker("Режим", selection: $mode) {
                    Text("Последовательно").tag("seq")
                    Text("Параллельно").tag("par")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(par ? "Каждый день — немного из разных частей Библии" : "Читаете книги по порядку, понемногу каждый день")
            }
            if par { parallelBody } else { sequentialBody }
            Section {
                Button {
                    create()
                } label: {
                    HStack {
                        Spacer()
                        Label(startLabel, systemImage: "play.fill").font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canStart || module == nil)
                .listRowBackground(Color.clear)
            } footer: {
                if module == nil { Text("Сначала скачайте перевод Библии.") }
            }
        }
        .navigationTitle("Свой план")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let m = message {
                Text(m).padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule()).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: message)
        .animation(.default, value: mode)
        .animation(.default, value: parMode)
        .animation(.default, value: scope)
    }

    private var startLabel: String {
        if par && !period && parDays == 0 || needOwn { return String(localized: "Выберите книги") }
        return String(localized: "Начать")
    }

    // MARK: последовательно

    @ViewBuilder private var sequentialBody: some View {
        Section("Что читать") {
            ForEach(scopes, id: \.id) { s in
                Button { scope = s.id } label: {
                    HStack {
                        Label(LocalizedStringKey(s.label), systemImage: s.icon).foregroundStyle(.primary)
                        Spacer()
                        if scope == s.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
        }
        if scope == "own" { Section { BookPicker(selected: Set(own), onChange: setOwn) } }
        daysSection(binding: $days, books: scopeBooks(scope))
    }

    // MARK: параллельно

    @ViewBuilder private var parallelBody: some View {
        Section {
            Picker("Режим", selection: $parMode) {
                Text("Глав в день").tag("perday")
                Text("За срок").tag("period")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            ForEach(PlanLogic.streams) { s in
                streamRow(s)
            }
        } header: {
            Text(period ? "Разделы" : "Разделы и глав в день")
        }
        if streams["own"] != nil { Section { BookPicker(selected: Set(own), onChange: setOwn) } }
        if period {
            daysSection(binding: $periodDays, books: parBooks)
        } else {
            Section {
                let first = PlanLogic.firstDayText(sel, chapters: chapters)
                if !first.isEmpty {
                    Text("Первый день: \(first)").font(.subheadline.weight(.semibold))
                }
                Text("Псалтирь и Притчи читаются по кругу, остальные разделы — один раз. Чтобы все разделы закончились в один день, выберите «За срок».")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func streamRow(_ s: PlanStream) -> some View {
        let on = streams[s.key] != nil
        return HStack {
            Button {
                var d = streams
                if on { d.removeValue(forKey: s.key) } else { d[s.key] = 1 }
                setStreams(d)
            } label: {
                HStack {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                    Text(LocalizedStringKey(s.label)).foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if on && !period {
                let n = streams[s.key] ?? 1
                Stepper("\(n)", value: Binding(get: { n }, set: { v in
                    var d = streams
                    d[s.key] = min(10, max(1, v))
                    setStreams(d)
                }), in: 1...10)
                .fixedSize()
                .labelsHidden()
                Text("\(n) гл. в день").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: срок

    @ViewBuilder private func daysSection(binding: Binding<Int>, books: [String]) -> some View {
        Section {
            Stepper(value: binding, in: 7...730, step: binding.wrappedValue < 60 ? 1 : 10) {
                HStack {
                    Text("За сколько дней")
                    Spacer()
                    Text("\(binding.wrappedValue) дн.").foregroundStyle(.secondary)
                }
            }
            if let line = loadLine(books: books, days: binding.wrappedValue) {
                Text(line.text).font(.footnote.weight(.semibold))
                    .foregroundStyle(line.heavy ? Color.red : .secondary)
            }
            ForEach(Array(presets.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.0) { n, label in
                        Button { binding.wrappedValue = n } label: {
                            Text(LocalizedStringKey(label)).font(.subheadline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(binding.wrappedValue == n ? .accentColor : .gray)
                    }
                }
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("За сколько дней")
        }
    }

    /// «≈ 13 гл. в день · до 24 января»; больше часа чтения в день (~8 с на стих) — красным
    private func loadLine(books: [String], days: Int) -> (text: String, heavy: Bool)? {
        let ch = chapters(books)
        guard !ch.isEmpty, days > 0 else { return nil }
        let d = min(days, ch.count)
        let verses = ch.reduce(0) { $0 + $1.n }
        let per = max(1, Int((Double(ch.count) / Double(d)).rounded()))
        let minutes = max(1, Int((Double(verses) / Double(d) * 8 / 60).rounded()))
        let text = String(localized: "≈ \(per) гл. в день") + " · " + String(localized: "до") + " " + endText(d)
        return (text, minutes > 60)
    }

    private func endText(_ days: Int) -> String {
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .day, value: max(days, 1) - 1, to: now) ?? now
        let f = DateFormatter()
        f.locale = Locale(identifier: lang)
        let sameYear = cal.component(.year, from: end) == cal.component(.year, from: now)
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMMM" : "dMMMMyyyy")
        return f.string(from: end)
    }

    // MARK: создание

    private func ownLabel() -> String {
        let names = own.compactMap { Books.info($0)?.name }
        return names.count > 2 ? "\(names.prefix(2).joined(separator: ", ")) и ещё \(names.count - 2)" : names.joined(separator: ", ")
    }

    private func create() {
        var name = ""
        var readings: [[String]] = []
        if par {
            let list = sel
            readings = PlanLogic.makeParallelPlan(list, chapters: chapters, period: period ? periodDays : nil)
            let parts = list.map { x -> String in
                x.key == "own" ? ownLabel() : (PlanLogic.streams.first { $0.key == x.key }?.short ?? x.key)
            }.joined(separator: " + ")
            name = period ? "\(parts) за \(readings.count) дн." : "\(parts) параллельно"
        } else {
            let books = scopeBooks(scope)
            readings = PlanLogic.splitChapters(chapters(books), days: days)
            let label = scope == "own" ? ownLabel() : (scopes.first { $0.id == scope }?.label ?? "")
            name = "\(label) за \(readings.count) дн."
        }
        guard !readings.isEmpty else {
            flash(String(localized: "Не удалось составить план"))
            return
        }
        if plans.has(planId: "custom", name: name, readings: readings) {
            flash(String(localized: "Этот план уже добавлен"))
            return
        }
        plans.add(Plan(
            uid: String(Int(Date().timeIntervalSince1970 * 1000), radix: 36),
            planId: "custom",
            name: name,
            readings: readings,
            calendar: false,
            start: PlanLogic.localDate()
        ))
        dismiss()
    }

    private func flash(_ s: String) {
        message = s
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if message == s { message = nil }
        }
    }
}

final class PlanChapterCache {
    var d: [String: [ChapterRef]] = [:]
}

/// Свои книги: сетка коротких названий по Заветам, нажатие — выбрать или убрать
struct BookPicker: View {
    let selected: Set<String>
    let onChange: (Set<String>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([("OT", "Ветхий Завет"), ("NT", "Новый Завет")], id: \.0) { t, title in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(Books.all.filter { $0.t == t }) { b in
                            let on = selected.contains(b.id)
                            Button {
                                var s = selected
                                if on { s.remove(b.id) } else { s.insert(b.id) }
                                onChange(s)
                            } label: {
                                Text(b.short.replacingOccurrences(of: ".", with: ""))
                                    .font(.subheadline)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !selected.isEmpty {
                Text("Выбрано книг: \(selected.count)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
