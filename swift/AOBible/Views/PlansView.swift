import SwiftUI

/// Планы чтения: «Стих дня», статистика, активные планы с отметками, каталог планов и свой план
struct PlansView: View {
    @EnvironmentObject private var plans: PlansStore
    @State private var remindOn = Reminders.isOn
    @State private var remindTime: Date = {
        let p = Reminders.time.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(hour: p.first ?? 20, minute: p.count > 1 ? p[1] : 0)) ?? Date()
    }()
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
                Section {
                    Toggle("Напоминать о чтении", isOn: Binding(get: { remindOn }, set: { on in
                        if on {
                            Task {
                                let ok = await Reminders.requestAccess()
                                remindOn = ok
                                Reminders.isOn = ok
                                if !ok { flash("Уведомления запрещены — разрешите их в настройках телефона") }
                                Reminders.schedule(plans.plans)
                            }
                        } else {
                            remindOn = false
                            Reminders.isOn = false
                            Reminders.schedule(plans.plans)
                        }
                    }))
                    if remindOn {
                        DatePicker("Время", selection: $remindTime, displayedComponents: .hourAndMinute)
                            .onChange(of: remindTime) { _, t in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                                Reminders.time = String(format: "%02d:%02d", c.hour ?? 20, c.minute ?? 0)
                                Reminders.schedule(plans.plans)
                            }
                    }
                }
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
    @State private var imageReq: ImageRequest?

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
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            imageReq = ImageRequest(text: v.text, ref: label)
                        } label: {
                            Label("Картинка", systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.black.opacity(0.45), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: "«\(v.text)» — \(label) (\(v.module.name))") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.45), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
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
        .sheet(item: $imageReq) { VerseImageSheet(text: $0.text, ref: $0.ref) }
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
            Section {
                if added {
                    Label("План уже добавлен", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button {
                        Task {
                            starting = true
                            await onStart()
                            starting = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if starting { ProgressView() } else { Text("Начать план").font(.headline) }
                            Spacer()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .listRowBackground(Color.clear)
                    .disabled(starting)
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
    @State private var showDay = false

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
            if today < total {
                Button { showDay = true } label: {
                    Label("Читать весь день", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showDay) { PlanDayView(uid: plan.uid, day: today) }
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
