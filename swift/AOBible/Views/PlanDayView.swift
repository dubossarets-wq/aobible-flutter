import SwiftUI

/// Весь день плана одной страницей: отрывки по порядку, у каждого — отметка «прочитано»; всё прочитано — день закрыт
struct PlanDayView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var plans: PlansStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var pal
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("fontFamily") private var fontFamily = "system"
    @AppStorage("fontWeight") private var fontWeight = 400.0
    @AppStorage("lineHeight") private var lineHeight = 1.45
    @Environment(\.openVerse) private var openVerse
    let uid: String
    @State private var cur: Int
    @State private var message: String?
    private var day: Int { cur }

    init(uid: String, day: Int) {
        self.uid = uid
        _cur = State(initialValue: day)
    }

    private var module: InstalledModule? {
        store.module(panes.primaryModule) ?? store.bibles.first
    }

    var body: some View {
        NavigationStack {
            if let plan = plans.plans.first(where: { $0.uid == uid }), let m = module {
                let units = PlanLogic.dayUnits(plan, day)
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 1).id("top")
                        ForEach(units.indices, id: \.self) { i in
                            let u = units[i]
                            let done = PlanLogic.unitDone(plan, day, u.key)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(PlanLogic.readingLabel(u.key))
                                        .font(.title3.weight(.bold))
                                    Spacer()
                                    Button {
                                        plans.mark(uid: uid, day: day, keys: [u.key])
                                    } label: {
                                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundStyle(done ? Color.green : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                ForEach(verses(m, u)) { v in
                                    Text("\(v.num) ").font(.system(size: fontSize * 0.62, weight: .semibold)).foregroundStyle(pal.verseNum)
                                        + Text(Markup.plain(v.text))
                                }
                                .font(ReadingFonts.font(fontFamily, size: fontSize, weight: fontWeight))
                                .lineSpacing(fontSize * (lineHeight - 1))
                                // дочитали отрывок до конца и провели над ним достаточно времени — он отмечается сам
                                if !done {
                                    AutoMarker(seconds: PlanLogic.minSeconds(verses(m, u).count)) {
                                        let finished = plans.mark(uid: uid, day: day, keys: [u.key])
                                        flash(finished ? "План на сегодня выполнен 🎉" : "✓ Прочитано")
                                    }
                                }
                            }
                        }
                        if PlanLogic.dayDone(plan, day) { nextSteps(plan, units, proxy) }
                    }
                    .padding(16)
                }
                .overlay(alignment: .top) {
                    if let msg = message {
                        Text(msg).padding(.horizontal, 16).padding(.vertical, 10)
                            .glassEffect(.regular, in: Capsule()).padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: message)
                }
                .background(pal.bg)
                .navigationTitle("\(plan.name) · день \(day + 1)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Прочитано") {
                            plans.mark(uid: uid, day: day, keys: units.map { $0.key })
                            dismiss()
                        }
                        .disabled(PlanLogic.dayDone(plan, day))
                    }
                }
            } else {
                ContentUnavailableView("Нет перевода или плана", systemImage: "book")
            }
        }
    }

    private func flash(_ s: String) {
        message = s
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if message == s { message = nil }
        }
    }

    /// День прочитан: «Дальше по плану» или «Читать дальше — вне плана»
    @ViewBuilder private func nextSteps(_ plan: Plan, _ units: [ReadingUnit], _ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            if cur + 1 < plan.readings.count {
                Button {
                    cur += 1
                    proxy.scrollTo("top", anchor: .top)
                } label: {
                    Label("Дальше по плану", systemImage: "forward.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if let last = units.last {
                Button {
                    dismiss()
                    openVerse(last.book, last.chapter + 1, 1)
                } label: {
                    Label("Читать дальше — вне плана", systemImage: "book").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .padding(.top, 8)
    }

    private func verses(_ m: InstalledModule, _ u: ReadingUnit) -> [Verse] {
        let all = store.verses(module: m.id, book: u.book, chapter: u.chapter)
        guard u.to != nil else { return all }
        return all.filter { $0.num >= u.from && $0.num <= (u.to ?? u.from) }
    }
}

/// Невидимая метка под отрывком: пока она на экране `seconds` секунд подряд — вызывает действие
private struct AutoMarker: View {
    let seconds: Double
    let action: () -> Void
    @State private var task: Task<Void, Never>?

    var body: some View {
        Color.clear.frame(height: 1)
            .onAppear {
                task = Task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    if !Task.isCancelled { action() }
                }
            }
            .onDisappear { task?.cancel() }
    }
}
