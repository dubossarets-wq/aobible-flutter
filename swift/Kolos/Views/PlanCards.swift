import SwiftUI

struct DayRef: Identifiable {
    let id: Int
}

/// Конец плана: «до 14 января»
private func planEnd(_ plan: Plan, _ lang: String) -> String? {
    guard !plan.calendar else { return nil }
    let cal = Calendar.current
    guard let end = cal.date(byAdding: .day, value: max(plan.readings.count, 1) - 1, to: PlanLogic.day0(plan.start)) else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: lang)
    let same = cal.component(.year, from: end) == cal.component(.year, from: Date())
    f.setLocalizedDateFormatFromTemplate(same ? "dMMMM" : "dMMMMyyyy")
    return f.string(from: end)
}

/// Карточка плана на вкладке «Планы»: заголовок с полосой прогресса, лента дней вокруг сегодняшнего, отрывки дня, «Читать»/«Догнать»,
/// меню с удалением плана
struct PlanCard: View {
    @EnvironmentObject private var plans: PlansStore
    @Environment(\.openVerse) private var openVerse
    @AppStorage("interfaceLanguage") private var lang = "ru"
    let plan: Plan
    @State private var dayRef: DayRef?
    @State private var confirmDelete = false

    var body: some View {
        let today = PlanLogic.planToday(plan)
        let total = plan.readings.count
        let readings = today < total ? plan.readings[today] : []
        let behind = PlanLogic.behindDays(plan)
        let doneDays = plan.done.count
        VStack(alignment: .leading, spacing: 18) {
            header(today: today, total: total, doneDays: doneDays)
            strip(today: today, total: total)
            if !readings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сегодня")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    VStack(spacing: 0) {
                        ForEach(Array(readings.enumerated()), id: \.offset) { i, r in
                            readingRow(r, today: today)
                            if i < readings.count - 1 { Divider().padding(.leading, 40) }
                        }
                    }
                }
            } else if today >= total, total > 0 {
                Label("План пройден — поздравляем!", systemImage: "party.popper.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
            if today < total || !behind.isEmpty {
                HStack(spacing: 10) {
                    if today < total {
                        bigButton("Читать день", icon: "book.fill", fill: Color.accentColor, text: .white) { dayRef = DayRef(id: today) }
                    }
                    if let first = behind.first {
                        bigButton("Догнать · \(behind.count)", icon: "forward.end.fill", fill: Color.orange.opacity(0.16), text: .orange) { dayRef = DayRef(id: first) }
                    }
                }
            }
            NavigationLink {
                PlanDetailView(uid: plan.uid)
            } label: {
                HStack {
                    Label("Все дни", systemImage: "list.bullet")
                    Spacer()
                    Text("\(doneDays) из \(total)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(item: $dayRef) { PlanDayView(uid: plan.uid, day: $0.id) }
        .alert("Удалить план «\(plan.name)»?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { plans.remove(plan.uid) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Отметки прочитанного пропадут.")
        }
    }

    /// Отрывок дня: кружок «прочитано» и название (открывает текст)
    private func readingRow(_ r: String, today: Int) -> some View {
        let done = PlanLogic.readingDone(plan, today, r)
        return HStack(spacing: 12) {
            Button {
                plans.mark(uid: plan.uid, day: today, keys: PlanLogic.readingUnits(r).map { $0.key })
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 28)
            }
            .buttonStyle(.plain)
            Button {
                let t = PlanLogic.readingTarget(r)
                openVerse(t.book, t.chapter, t.verse)
            } label: {
                HStack {
                    Text(PlanLogic.readingLabel(r))
                        .font(.body.weight(.medium))
                        .foregroundStyle(done ? .secondary : .primary)
                        .strikethrough(done, color: .secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    /// Крупная кнопка-капсула: текст и значок точно по центру
    private func bigButton(_ title: LocalizedStringKey, icon: String, fill: Color, text: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.headline)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Заголовок: название, «День N из M · до …», меню; под ним — полоса прогресса с процентом
    private func header(today: Int, total: Int, doneDays: Int) -> some View {
        let part = Double(doneDays) / Double(max(1, total))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("День \(min(today + 1, total)) из \(total)" + (planEnd(plan, lang).map { " · до \($0)" } ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Menu {
                    NavigationLink { PlanDetailView(uid: plan.uid) } label: { Label("Все дни", systemImage: "list.bullet") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить план", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Ещё")
            }
            HStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(Color.accentColor)
                            .frame(width: part > 0 ? max(8, g.size.width * part) : 0)
                    }
                }
                .frame(height: 8)
                Text("\(Int((part * 100).rounded())) %")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Семь дней вокруг сегодняшнего: сегодня — закрашен акцентом, прочитан — зелёная галочка, пропущен — оранжевый
    private func strip(today: Int, total: Int) -> some View {
        let start = max(0, min(today - 3, total - 7))
        let days = Array(start..<min(total, start + 7))
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let done = PlanLogic.dayDone(plan, d)
                let missed = d < today && !done
                let isToday = d == today
                Button { dayRef = DayRef(id: d) } label: {
                    ZStack {
                        Circle().fill(
                            done ? Color.green
                                : isToday ? Color.accentColor
                                : missed ? Color.orange.opacity(0.18)
                                : Color.secondary.opacity(0.12)
                        )
                        if done {
                            Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.white)
                        } else {
                            Text("\(d + 1)")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(isToday ? Color.white : (missed ? Color.orange : Color.primary.opacity(0.7)))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("День \(d + 1)")
            }
        }
    }
}

/// Все дни плана: сгруппированы по 30, прокрутка к сегодняшнему дню сама, переход к нужному блоку, фильтр «не прочитанные»,
/// удаление плана — в меню сверху (не надо листать вниз)
struct PlanDetailView: View {
    @EnvironmentObject private var plans: PlansStore
    @Environment(\.dismiss) private var dismiss
    let uid: String
    @State private var confirmDelete = false
    @State private var onlyUnread = false
    @State private var dayRef: DayRef?

    private struct Block: Identifiable {
        let id: Int
        let range: Range<Int>
    }

    private func blocks(_ total: Int) -> [Block] {
        let size = total > 60 ? 30 : max(total, 1)
        return stride(from: 0, to: max(total, 1), by: size).enumerated().map { i, s in Block(id: i, range: s..<min(total, s + size)) }
    }

    var body: some View {
        if let plan = plans.plans.first(where: { $0.uid == uid }) {
            let today = PlanLogic.planToday(plan)
            let total = plan.readings.count
            let all = blocks(total)
            ScrollViewReader { proxy in
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(plan.name).font(.headline)
                            ProgressView(value: Double(plan.done.count), total: Double(max(1, total)))
                            HStack {
                                Text("Прочитано дней: \(plan.done.count) из \(total)")
                                Spacer()
                                Text("Осталось: \(max(0, total - plan.done.count))")
                            }
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            withAnimation { proxy.scrollTo("d\(min(today, max(total - 1, 0)))", anchor: .center) }
                        } label: {
                            Label("К сегодняшнему дню · день \(min(today + 1, total))", systemImage: "scope")
                        }
                    }
                    ForEach(all) { b in
                        let days = b.range.filter { !onlyUnread || !PlanLogic.dayDone(plan, $0) }
                        if !days.isEmpty {
                            Section {
                                ForEach(days, id: \.self) { d in row(plan, d, today) }
                            } header: {
                                let done = b.range.filter { PlanLogic.dayDone(plan, $0) }.count
                                Text("Дни \(b.range.lowerBound + 1)–\(b.range.upperBound) · \(done)/\(b.range.count)")
                            }
                            .id("b\(b.id)")
                        }
                    }
                }
                .navigationTitle("План")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle("Только непрочитанные", isOn: $onlyUnread)
                            if all.count > 1 {
                                Menu("Перейти к…") {
                                    ForEach(all) { b in
                                        Button("Дни \(b.range.lowerBound + 1)–\(b.range.upperBound)") {
                                            withAnimation { proxy.scrollTo("b\(b.id)", anchor: .top) }
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить план", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        proxy.scrollTo("d\(min(today, max(total - 1, 0)))", anchor: .center)
                    }
                }
                .sheet(item: $dayRef) { PlanDayView(uid: uid, day: $0.id) }
                .alert("Удалить план «\(plan.name)»?", isPresented: $confirmDelete) {
                    Button("Удалить", role: .destructive) {
                        plans.remove(uid)
                        dismiss()
                    }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("Отметки прочитанного пропадут.")
                }
            }
        } else {
            ContentUnavailableView("План удалён", systemImage: "calendar.badge.minus")
        }
    }

    private func row(_ plan: Plan, _ d: Int, _ today: Int) -> some View {
        let done = PlanLogic.dayDone(plan, d)
        let missed = d < today && !done
        return Button {
            dayRef = DayRef(id: d)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : (d == today ? "circle.inset.filled" : "circle"))
                    .foregroundStyle(done ? Color.green : (d == today ? Color.accentColor : (missed ? Color.orange : Color.secondary)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("День \(d + 1)").foregroundStyle(.primary)
                        if d == today { Text("сегодня").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                        if missed { Text("пропущен").font(.caption).foregroundStyle(.orange) }
                    }
                    Text(plan.readings[d].map { PlanLogic.readingLabel($0) }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .id("d\(d)")
        .swipeActions(edge: .trailing) {
            if !done {
                Button("Прочитано") {
                    plans.mark(uid: plan.uid, day: d, keys: PlanLogic.dayUnits(plan, d).map { $0.key })
                }
                .tint(.green)
            }
        }
    }
}
