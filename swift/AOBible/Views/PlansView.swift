import SwiftUI

/// Планы чтения: «Стих дня», статистика, активные планы с отметками, каталог планов и свой план
struct PlansView: View {
    @EnvironmentObject private var plans: PlansStore
    @State private var catalog: [PlanMeta] = []
    @State private var catalogFailed = false
    @State private var busy: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VerseOfDayCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    StatsCard(stats: PlanLogic.stats(plans.log))
                }
                ForEach(plans.plans) { p in
                    Section {
                        PlanCard(plan: p)
                    }
                }
                Section {
                    ForEach(catalog) { m in
                        Button {
                            Task { await start(m) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).foregroundStyle(.primary)
                                    if let s = m.short {
                                        Text("\(s) · \(m.days) дн.").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if busy == m.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle").foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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
        busy = m.id
        defer { busy = nil }
        guard let j = await Net.json("plans/" + m.file), let readings = j["readings"] as? [[String]], !readings.isEmpty else {
            flash("План не загрузился")
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
                    Text(v.text)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                    Rectangle().fill(.white.opacity(0.7)).frame(width: 40, height: 2)
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack {
                        Button {
                            openVerse(v.book, v.chapter, v.verse)
                        } label: {
                            Label("Читать", systemImage: "book")
                        }
                        .buttonStyle(.glassProminent)
                        ShareLink(item: "«\(v.text)» — \(label) (\(v.module.name))") {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.glass)
                    }
                } else {
                    Text("Скачайте перевод Библии, чтобы увидеть стих дня.")
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .task(id: moduleId + "\(store.installed.count)") {
            verse = VerseOfDay.load(store: store, preferred: moduleId)
            if photo == nil, let j = await Net.json("images/verse-bg/index.json"),
               let list = j["images"] as? [[String: Any]], !list.isEmpty,
               let file = list[VerseOfDay.dayOfYear() % list.count]["file"] as? String {
                photo = URL(string: Net.bases[0] + "images/verse-bg/" + file)
            }
        }
    }
}

// MARK: - Статистика

struct StatsCard: View {
    let stats: ReadStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                stat("\(stats.today)", "сегодня")
                stat("\(stats.week)", "за неделю")
                stat("\(stats.total)", "всего глав")
                stat("\(stats.streak)", "дней подряд")
            }
            HStack(alignment: .bottom, spacing: 8) {
                let top = max(1, stats.days7.map { $0.n }.max() ?? 1)
                ForEach(stats.days7) { d in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(d.n > 0 ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(height: d.n > 0 ? max(8, 56 * CGFloat(d.n) / CGFloat(top)) : 4)
                        Text(weekday(d.day)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ n: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.title2.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

struct PlanCard: View {
    @EnvironmentObject private var plans: PlansStore
    @Environment(\.openVerse) private var openVerse
    let plan: Plan

    var body: some View {
        let today = PlanLogic.planToday(plan)
        let total = plan.readings.count
        let readings = today < total ? plan.readings[today] : []
        let behind = PlanLogic.behindDays(plan)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name).font(.headline)
                    Text("День \(today + 1) из \(total)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                ProgressRing(value: Double(plan.done.count) / Double(max(1, total)))
            }
            if !behind.isEmpty {
                Text("Пропущено дней: \(behind.count)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(readings, id: \.self) { r in
                let done = PlanLogic.readingDone(plan, today, r)
                HStack(spacing: 12) {
                    Button {
                        plans.mark(uid: plan.uid, day: today, keys: PlanLogic.readingUnits(r).map { $0.key })
                    } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(done ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        let t = PlanLogic.readingTarget(r)
                        openVerse(t.book, t.chapter, t.verse)
                    } label: {
                        HStack {
                            Text(PlanLogic.readingLabel(r)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            NavigationLink {
                PlanDetailView(uid: plan.uid)
            } label: {
                Text("Все дни и настройки")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlanDetailView: View {
    @EnvironmentObject private var plans: PlansStore
    @Environment(\.openVerse) private var openVerse
    @Environment(\.dismiss) private var dismiss
    let uid: String
    @State private var confirmDelete = false

    var body: some View {
        if let plan = plans.plans.first(where: { $0.uid == uid }) {
            let today = PlanLogic.planToday(plan)
            List {
                Section {
                    Text(plan.name).font(.headline)
                    Text("Выполнено дней: \(plan.done.count) из \(plan.readings.count)").foregroundStyle(.secondary)
                }
                Section("Дни") {
                    ForEach(plan.readings.indices, id: \.self) { d in
                        let done = PlanLogic.dayDone(plan, d)
                        Button {
                            if let r = plan.readings[d].first {
                                let t = PlanLogic.readingTarget(r)
                                openVerse(t.book, t.chapter, t.verse)
                            }
                        } label: {
                            HStack {
                                Image(systemName: done ? "checkmark.circle.fill" : (d == today ? "circle.inset.filled" : "circle"))
                                    .foregroundStyle(done ? Color.green : (d == today ? Color.accentColor : Color.secondary))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("День \(d + 1)" + (d == today ? " · сегодня" : "")).foregroundStyle(.primary)
                                    Text(plan.readings[d].map { PlanLogic.readingLabel($0) }.joined(separator: " · "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if !done {
                                Button("Прочитано") {
                                    plans.mark(uid: uid, day: d, keys: PlanLogic.dayUnits(plan, d).map { $0.key })
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                Section {
                    Button("Удалить план", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("План")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Удалить план «\(plan.name)»? Отметки прочитанного пропадут.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    plans.remove(uid)
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("План удалён", systemImage: "calendar.badge.minus")
        }
    }
}

// MARK: - Свой план

struct CustomPlanView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var plans: PlansStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var panes: PanesStore
    private var moduleId: String { panes.primaryModule }
    @State private var scope = "all"
    @State private var days = 365

    private let scopes: [(String, String, [String])] = [
        ("all", "Вся Библия", []),
        ("ot", "Ветхий Завет", []),
        ("nt", "Новый Завет", []),
        ("gospels", "Евангелия", ["Matt", "Mark", "Luke", "John"]),
        ("ps", "Псалтирь", ["Ps"]),
    ]

    private var module: InstalledModule? {
        store.module(moduleId) ?? store.bibles.first
    }

    private func books() -> [String] {
        guard let m = module else { return [] }
        let have = Set(m.books.map { $0.id })
        let ids: [String]
        switch scope {
        case "all": ids = Books.all.filter { $0.t == "OT" || $0.t == "NT" }.map { $0.id }
        case "ot": ids = Books.all.filter { $0.t == "OT" }.map { $0.id }
        case "nt": ids = Books.all.filter { $0.t == "NT" }.map { $0.id }
        default: ids = scopes.first { $0.0 == scope }?.2 ?? []
        }
        return ids.filter { have.contains($0) }
    }

    var body: some View {
        let label = scopes.first { $0.0 == scope }?.1 ?? ""
        Form {
            Section("Что читать") {
                Picker("Что читать", selection: $scope) {
                    ForEach(scopes, id: \.0) { s in
                        Text(s.1).tag(s.0)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("За сколько дней") {
                Stepper(value: $days, in: 7...730, step: days < 60 ? 1 : 10) {
                    Text("\(days) дн.")
                }
            }
            Section {
                Button("Создать план") { create(label) }
                    .disabled(module == nil)
            } footer: {
                if module == nil {
                    Text("Сначала скачайте перевод Библии.")
                }
            }
        }
        .navigationTitle("Свой план")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create(_ label: String) {
        guard let m = module else { return }
        let readings = PlanLogic.splitChapters(store.chapterList(module: m, books: books()), days: days)
        guard !readings.isEmpty else { return }
        plans.add(Plan(
            uid: String(Int(Date().timeIntervalSince1970 * 1000), radix: 36),
            planId: "custom",
            name: "\(label) за \(readings.count) дн.",
            readings: readings,
            calendar: false,
            start: PlanLogic.localDate()
        ))
        dismiss()
    }
}
