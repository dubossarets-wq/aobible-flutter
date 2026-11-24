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

    /// Выбранные неканонические книги (id через запятую); пусто — в планы не входят
    @AppStorage("cp.dcSel") private var dcSelRaw = ""
    @State private var dcOpen = false
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
        return Books.all.filter { set.contains($0.id) && ($0.dc != true || dcSel.contains($0.id)) }.map { $0.id }
    }

    private var dcSel: Set<String> { Set(dcSelRaw.split(separator: ",").map(String.init)) }

    private func setDC(_ ids: Set<String>) { dcSelRaw = ids.sorted().joined(separator: ",") }

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
            var c = store.chapterList(module: m, books: [b])
            // в основном переводе книги нет (RST+ без неканонических) — главы считаем по другому, где она есть
            if c.isEmpty {
                // в основном переводе книги нет — берём другой, где она есть: «Синодальный с неканоническими» первым, затем любой
                // (Енох, Юбилеи и Завещания лежат только в модуле «Неканонические книги»)
                let alts = [store.module("rst-dc")].compactMap { $0 } + store.bibles.filter { $0.id != m.id && $0.id != "rst-dc" }
                if let alt = alts.first(where: { $0.books.contains { $0.id == b } }) { c = store.chapterList(module: alt, books: [b]) }
            }
            cache.d[m.id + b] = c
            return c
        }
    }

    private func scopeBooks(_ id: String) -> [String] {
        switch id {
        case "all": return Books.all.filter { ($0.t == "OT" || $0.t == "NT") && ($0.dc != true || dcSel.contains($0.id)) }.map { $0.id }
        case "ot": return Books.all.filter { $0.t == "OT" && ($0.dc != true || dcSel.contains($0.id)) }.map { $0.id }
        case "nt": return Books.all.filter { $0.t == "NT" }.map { $0.id }
        case "own": return own
        default: return scopes.first { $0.id == id }?.books ?? []
        }
    }

    private var par: Bool { mode == "par" }
    private var period: Bool { par && parMode == "period" }
    private var sel: [StreamSel] { PlanLogic.streamList(on: streams, own: own, dcBooks: dcSel) }
    private var parBooks: [String] { sel.flatMap { $0.books } }
    private var parDays: Int { period ? 0 : PlanLogic.parallelDays(sel, chapters: chapters) }
    private var needOwn: Bool { (par ? streams["own"] != nil : scope == "own") && own.isEmpty }
    private var canStart: Bool {
        if needOwn { return false }
        if par && !period { return parDays > 0 }
        return !(par ? parBooks : scopeBooks(scope)).isEmpty
    }

    // MARK: вид

    private var cardColor: Color { Color(.secondarySystemGroupedBackground) }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func caption(_ s: LocalizedStringKey) -> some View {
        Text(s)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.horizontal, 6)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CapsuleSwitcher(options: [("seq", String(localized: "Последовательно")), ("par", String(localized: "Параллельно"))], selection: $mode)
                Text(par ? "Каждый день — немного из разных частей Библии" : "Читаете книги по порядку, понемногу каждый день")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                // содержимое режима уезжает в сторону своей вкладки и мягко гаснет, новое въезжает с той же стороны
                if par {
                    VStack(alignment: .leading, spacing: 18) { parallelBody }
                        .transition(.offset(x: 44).combined(with: .opacity))
                } else {
                    VStack(alignment: .leading, spacing: 18) { sequentialBody }
                        .transition(.offset(x: -44).combined(with: .opacity))
                }
                if module == nil {
                    Text("Сначала скачайте перевод Библии.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        // кнопка «Начать» закреплена внизу — не нужно листать до конца
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                create()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(startLabel).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canStart || module == nil)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
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
        .animation(.smooth(duration: 0.36), value: mode)
        .animation(.snappy, value: parMode)
        .animation(.snappy, value: scope)
    }

    private var startLabel: String {
        if needOwn || (par && !period && parDays == 0) { return String(localized: "Выберите книги") }
        let n = par ? (period ? periodDays : parDays) : days
        return String(localized: "Начать") + " · " + String(localized: "\(n) дн.")
    }

    // MARK: последовательно

    @ViewBuilder private var sequentialBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Что читать")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(scopes, id: \.id) { s in
                    let full = s.id == "all" || s.id == "own"
                    scopeTile(s)
                        .gridCellColumns(full ? 2 : 1)
                }
            }
        }
        dcToggle
        if scope == "own" { card { BookPicker(selected: Set(own), dcBooks: dcSel, onChange: setOwn) } }
        daysCard(binding: $days, books: scopeBooks(scope))
    }

    @ViewBuilder private func scopeTile(_ s: (id: String, label: String, icon: String, books: [String])) -> some View {
        let on = scope == s.id
        Button {
            scope = s.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: s.icon)
                    .font(.title3)
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .frame(width: 26)
                Text(LocalizedStringKey(s.label))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(on ? Color.accentColor.opacity(0.12) : cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: параллельно

    @ViewBuilder private var parallelBody: some View {
        CapsuleSwitcher(options: [("perday", String(localized: "Глав в день")), ("period", String(localized: "За срок"))], selection: $parMode)
        VStack(alignment: .leading, spacing: 8) {
            caption(period ? "Разделы" : "Разделы и глав в день")
            VStack(spacing: 8) {
                ForEach(PlanLogic.streams) { s in streamRow(s) }
            }
        }
        dcToggle
        if streams["own"] != nil { card { BookPicker(selected: Set(own), dcBooks: dcSel, onChange: setOwn) } }
        if period {
            daysCard(binding: $periodDays, books: parBooks)
        } else {
            let first = PlanLogic.firstDayText(sel, chapters: chapters)
            card {
                VStack(alignment: .leading, spacing: 10) {
                    if !first.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Первый день").font(.caption).foregroundStyle(.secondary)
                                Text(first).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    Text("Псалтирь и Притчи читаются по кругу, остальные разделы — один раз. Чтобы все разделы закончились в один день, выберите «За срок».")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func streamRow(_ s: PlanStream) -> some View {
        let on = streams[s.key] != nil
        let n = streams[s.key] ?? 1
        return HStack(spacing: 12) {
            Button {
                var d = streams
                if on { d.removeValue(forKey: s.key) } else { d[s.key] = 1 }
                setStreams(d)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    Text(LocalizedStringKey(s.label))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if on && !period {
                HStack(spacing: 2) {
                    stepButton("minus", enabled: n > 1) { setPer(s.key, n - 1) }
                    Text("\(n)").font(.subheadline.weight(.bold).monospacedDigit()).frame(minWidth: 22)
                    stepButton("plus", enabled: n < 10) { setPer(s.key, n + 1) }
                }
                Text("гл./день").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(on ? Color.accentColor.opacity(0.08) : cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Неканонические книги, которые есть в тексте (в основном переводе их нет — главы берутся из «Синодального
    /// с неканоническими»)
    private var dcBooks: [BookInfo] {
        let have = Books.all.filter { $0.dc == true && !chapters([$0.id]).isEmpty }
        let rank = Dictionary(uniqueKeysWithValues: Self.dcOrder.enumerated().map { ($1, $0) })
        return have.sorted { (rank[$0.id] ?? 999) < (rank[$1.id] ?? 999) }
    }

    /// Порядок как в изданиях с неканоническими книгами: историческая и учительная, затем Маккавеи и Ездры, дополнения;
    /// после них — Енох, Юбилеи и Завещания двенадцати патриархов (по коленам)
    private static let dcOrder = ["1Esd", "Tob", "Jdt", "Wis", "Sir", "EpJer", "Bar", "PrAzar", "Sus", "Bel", "1Macc", "2Macc", "3Macc",
                                  "2Esd", "PrMan", "Ps151", "1En", "Jub", "TReu", "TSim", "TLevi", "TJud", "TIss", "TZeb", "TDan",
                                  "TNaph", "TGad", "TAsh", "TJos", "TBenj"]

    private func toggleDC(_ id: String) {
        var s = dcSel
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        setDC(s)
    }

    /// Неканонические книги: по умолчанию в планы не входят. Нажатие на блок раскрывает ПОД ним список книг —
    /// отметить, какие добавить в план, или «Добавить все»
    private var dcToggle: some View {
        let all = dcBooks
        let picked = dcSel.intersection(all.map(\.id))
        let allOn = !all.isEmpty && picked.count == all.count
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.32)) { dcOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text("Неканонические книги").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !picked.isEmpty {
                        Text(verbatim: "\(picked.count)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(dcOpen ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if dcOpen {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Выберите книги").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            setDC(allOn ? [] : Set(all.map(\.id)))
                        } label: {
                            Text(allOn ? "Убрать все" : "Добавить все")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.accentColor.opacity(0.13), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    ForEach(all) { b in
                        Divider().padding(.leading, 50)
                        let on = dcSel.contains(b.id)
                        Button { toggleDC(b.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                                Text(b.name).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    // Енох, Юбилеи и Завещания лежат в отдельном модуле — нет его, предлагаем скачать
                    if store.module("noncanon-ru") == nil, let e = store.catalogEntry("noncanon-ru") {
                        Divider().padding(.leading, 14)
                        Button {
                            Task {
                                await store.install(e)
                                cache.d.removeAll() // главы Еноха и других теперь есть
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(Color.accentColor)
                                Text(store.busy[e.id] ?? "Скачать: Енох, Юбилеи, Завещания патриархов").foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.busy[e.id] != nil)
                    }
                }
                .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: dcOpen) { if dcOpen, store.catalog.isEmpty { await store.loadCatalog() } }
    }

    private func setPer(_ key: String, _ v: Int) {
        var d = streams
        d[key] = min(10, max(1, v))
        setStreams(d)
    }

    private func stepButton(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    // MARK: срок

    @ViewBuilder private func daysCard(binding: Binding<Int>, books: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("За сколько дней")
            card {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Button { binding.wrappedValue = max(7, binding.wrappedValue - (binding.wrappedValue <= 60 ? 1 : 10)) } label: {
                            Image(systemName: "minus").font(.title3.weight(.bold)).frame(width: 48, height: 48)
                                .background(Color.secondary.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        VStack(spacing: 0) {
                            Text("\(binding.wrappedValue)")
                                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                                .contentTransition(.numericText())
                            Text(daysWord(binding.wrappedValue)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Button { binding.wrappedValue = min(730, binding.wrappedValue + (binding.wrappedValue < 60 ? 1 : 10)) } label: {
                            Image(systemName: "plus").font(.title3.weight(.bold)).frame(width: 48, height: 48)
                                .background(Color.secondary.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Slider(value: Binding(get: { Double(binding.wrappedValue) }, set: { binding.wrappedValue = Int($0) }), in: 7...730, step: 1)
                    if let line = loadLine(books: books, days: binding.wrappedValue) {
                        HStack(spacing: 8) {
                            Image(systemName: line.heavy ? "exclamationmark.triangle.fill" : "clock")
                            Text(line.text).font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(line.heavy ? Color.red : Color.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background((line.heavy ? Color.red : Color.secondary).opacity(0.1), in: Capsule())
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(presets.flatMap { $0 }, id: \.0) { n, label in
                            let on = binding.wrappedValue == n
                            Button { binding.wrappedValue = n } label: {
                                Text(LocalizedStringKey(label))
                                    .font(.subheadline.weight(on ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(on ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func daysWord(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        if lang == "ru" || lang == "uk" || lang == "be" {
            if m10 == 1 && m100 != 11 { return "день" }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return "дня" }
            return "дней"
        }
        return String(localized: "дн.")
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
            name = period ? "\(parts) за \(readings.count) \(PlanLogic.daysWord(readings.count))" : "\(parts) параллельно"
        } else {
            let books = scopeBooks(scope)
            readings = PlanLogic.splitChapters(chapters(books), days: days)
            let label = scope == "own" ? ownLabel() : (scopes.first { $0.id == scope }?.label ?? "")
            name = "\(label) за \(readings.count) \(PlanLogic.daysWord(readings.count))"
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
    /// Выбранные неканонические книги — только они показываются в «Своих книгах»
    var dcBooks: Set<String> = []
    let onChange: (Set<String>) -> Void

    private var groups: [(String, String, [BookInfo])] {
        var g: [(String, String, [BookInfo])] = [
            ("OT", "Ветхий Завет", Books.all.filter { $0.t == "OT" && $0.dc != true }),
            ("NT", "Новый Завет", Books.all.filter { $0.t == "NT" && $0.dc != true }),
        ]
        if !dcBooks.isEmpty { g.append(("DC", "Неканонические", Books.all.filter { $0.dc == true && dcBooks.contains($0.id) })) }
        return g
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.0) { _, title, books in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(books) { b in
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
