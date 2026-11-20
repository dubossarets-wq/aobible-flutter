import SwiftUI

/// Планы чтения: «Стих дня», статистика, активные планы с отметками, каталог планов и свой план
struct PlansView: View {
    @EnvironmentObject private var plans: PlansStore
    @State private var catalog: [PlanMeta] = []
    @State private var catalogFailed = false
    @State private var busy: String?
    @State private var message: String?

    /// Открыт внутри чужой навигации («Ещё»): без своей NavigationStack
    var embedded = false

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        Group {
            List {
                Section {
                    VerseOfDayCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    StatsCard(stats: PlanLogic.stats(plans.log))
                }
                RemindersSection(flash: flash)
                ForEach(plans.plans) { p in
                    Section {
                        PlanCard(plan: p)
                    }
                }
                Section {
                    ForEach(catalog) { m in
                        NavigationLink {
                            PlanPreview(meta: m, added: plans.has(planId: m.id, name: m.name)) { await start(m) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(m.name)
                                    if plans.has(planId: m.id, name: m.name) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                                if let s = m.short {
                                    Text("\(s) · \(m.days) дн.").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if catalogFailed {
                        Button("Не удалось загрузить список планов. Повторить") { Task { await loadCatalog() } }
                    }
                    NavigationLink {
                        CustomPlanView()
                    } label: {
                        Label("Свой план", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("Выберите план")
                }
            }
            .navigationTitle("Планы чтения")
            .task { await loadCatalog() }
            .overlay(alignment: .top) {
                if let m = message {
                    Text(m)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: message)
        }
    }

    private func loadCatalog() async {
        guard catalog.isEmpty, let j = await Net.json("plans/index.json"), let list = j["plans"] as? [[String: Any]] else {
            catalogFailed = catalog.isEmpty
            return
        }
        catalogFailed = false
        catalog = list.map { PlanMeta(json: $0) }
    }

    private func start(_ m: PlanMeta) async {
        if plans.has(planId: m.id, name: m.name) {
            flash("Этот план уже добавлен")
            return
        }
        busy = m.id
        defer { busy = nil }
        guard let j = await Net.json("plans/" + m.file), let readings = j["readings"] as? [[String]], !readings.isEmpty else {
            flash("План не загрузился")
            return
        }
        if plans.has(planId: j["id"] as? String ?? m.id, name: m.name) {
            flash("Этот план уже добавлен")
            return
        }
        let p = Plan(
            uid: String(Int(Date().timeIntervalSince1970 * 1000), radix: 36),
            planId: j["id"] as? String ?? m.id,
            name: j["name"] as? String ?? m.name,
            readings: readings,
            calendar: j["calendar"] as? Bool ?? false,
            start: PlanLogic.localDate()
        )
        plans.add(p)
        flash("План «\(p.name)» начат")
    }

    private func flash(_ s: String) {
        message = s
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if message == s { message = nil }
        }
    }
}

// MARK: - Стих дня

struct VerseOfDayCard: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.openVerse) private var openVerse
    @EnvironmentObject private var panes: PanesStore
    private var moduleId: String { panes.primaryModule }
    @AppStorage("interfaceLanguage") private var lang = "ru"
    @State private var verse: DayVerse?
    @State private var photo: URL?

    private var label: String {
        guard let v = verse else { return "" }
        let name = v.module.books.first { $0.id == v.book }?.name ?? Books.info(v.book)?.name ?? v.book
        return "\(name) \(v.chapter):\(v.verse)"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                AsyncImage(url: photo) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.4)
                }
            } else {
                LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text("Стих дня")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                if let v = verse {
                    Text(v.text).bidi(v.text)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                    Rectangle().fill(.white.opacity(0.7)).frame(width: 40, height: 2)
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(.white)
                } else {
                    Text("Скачайте перевод Библии, чтобы увидеть стих дня.")
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        // «Отправить» — сверху справа, с ровными отступами от краёв карточки
        .overlay(alignment: .topTrailing) {
            if let v = verse {
                ShareLink(item: "«\(v.text)» — \(label) (\(v.module.name))", preview: SharePreview("\(label) (\(v.module.name))")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.35), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(16)
                .accessibilityLabel("Поделиться")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        // нажатие на карточку — переход к стиху
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            if let v = verse { openVerse(v.book, v.chapter, v.verse) }
        }
        .accessibilityAddTraits(.isButton)
        .task(id: moduleId + lang + "\(store.installed.count)") {
            verse = VerseOfDay.load(store: store, preferred: moduleId, language: lang)
            if photo == nil, let j = await Net.json("images/verse-bg/index.json"),
               let list = j["images"] as? [[String: Any]], !list.isEmpty,
               let file = list[VerseOfDay.dayOfYear() % list.count]["file"] as? String {
                photo = URL(string: Net.bases[0] + "images/verse-bg/" + file)
            }
        }
    }
}

/// Описание готового плана: что в нём, сколько дней, чтения по дням; отсюда же план начинают
struct PlanPreview: View {
    let meta: PlanMeta
    let added: Bool
    let onStart: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var readings: [[String]] = []
    @State private var failed = false
    @State private var starting = false

    var body: some View {
        List {
            Section {
                if let d = meta.description, !d.isEmpty { Text(d) }
                if let s = meta.short { Text(s).foregroundStyle(.secondary) }
                LabeledContent("Длительность", value: "\(readings.isEmpty ? meta.days : readings.count) дн.")
                if !readings.isEmpty {
                    let n = readings.reduce(0) { $0 + $1.count }
                    LabeledContent("Отрывков всего", value: "\(n)")
                    LabeledContent("В день", value: String(format: "%.1f", Double(n) / Double(readings.count)))
                }
            }
            if added {
                Section {
                    Label("План уже добавлен", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            if failed {
                Section { Text("Не удалось загрузить состав плана").foregroundStyle(.secondary) }
            }
            if !readings.isEmpty {
                Section("Чтения по дням") {
                    ForEach(Array(readings.enumerated()), id: \.offset) { i, day in
                        HStack(alignment: .firstTextBaseline) {
                            Text("День \(i + 1)").foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                            Text(day.map { PlanLogic.readingLabel($0) }.joined(separator: " · "))
                        }
                    }
                }
            }
        }
        // «Начать» — как в «Своём плане»: крупная кнопка, закреплена внизу
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !added {
                Button {
                    Task {
                        starting = true
                        await onStart()
                        starting = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if starting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                            Text(String(localized: "Начать") + " · " + String(localized: "\(readings.isEmpty ? meta.days : readings.count) дн."))
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(starting)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(meta.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let j = await Net.json("plans/" + meta.file), let r = j["readings"] as? [[String]] {
                readings = r
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Статистика

struct StatsCard: View {
    let stats: ReadStats

    /// Доля Библии, прочитанная целиком (1189 глав)
    private var part: Double { min(1, Double(stats.total) / 1189) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                // кольцо «сколько Библии прочитано»
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: max(0.012, part))
                        .stroke(AngularGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, part))),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(part > 0 && part < 0.01 ? "<1%" : "\(Int(part * 100))%").font(.headline.weight(.bold))
                        Text("Библии").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 8) {
                    // серия дней — главное число: с пламенем
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.title3)
                            .foregroundStyle(stats.streak > 0 ? Color.orange : Color.secondary.opacity(0.4))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(stats.streak)").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("дней подряд").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        mini("\(stats.today)", "сегодня")
                        mini("\(stats.week)", "за неделю")
                        mini("\(stats.total)", "всего глав")
                    }
                }
                Spacer(minLength: 0)
            }
            // неделя: сегодняшний день — акцентом, остальные приглушены
            HStack(alignment: .bottom, spacing: 10) {
                let top = max(1, stats.days7.map { $0.n }.max() ?? 1)
                ForEach(stats.days7) { d in
                    let isToday = d.id == stats.days7.last?.id
                    VStack(spacing: 5) {
                        Text(d.n > 0 && isToday ? "\(d.n)" : " ")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Capsule()
                            .fill(d.n == 0 ? AnyShapeStyle(Color.secondary.opacity(0.2))
                                  : isToday ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.accentColor.opacity(0.4)))
                            .frame(height: d.n > 0 ? max(10, 40 * CGFloat(d.n) / CGFloat(top)) : 6)
                        Text(weekday(d.day))
                            .font(.caption2.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
        .padding(.vertical, 6)
    }

    private func mini(_ n: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).font(.headline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func weekday(_ day: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru")
        f.dateFormat = "EEEEE"
        return f.string(from: PlanLogic.day0(day)).uppercased()
    }
}

// MARK: - Активный план

struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(1, max(0.005, value)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value < 0.01 && value > 0 ? "<1%" : "\(Int(value * 100))%")
                .font(.caption2.weight(.semibold))
        }
        .frame(width: 48, height: 48)
    }
}

// MARK: - Свой план
