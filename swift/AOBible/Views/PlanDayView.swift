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
    let uid: String
    let day: Int

    private var module: InstalledModule? {
        store.module(panes.primaryModule) ?? store.bibles.first
    }

    var body: some View {
        NavigationStack {
            if let plan = plans.plans.first(where: { $0.uid == uid }), let m = module {
                let units = PlanLogic.dayUnits(plan, day)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
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
                            }
                        }
                    }
                    .padding(16)
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

    private func verses(_ m: InstalledModule, _ u: ReadingUnit) -> [Verse] {
        let all = store.verses(module: m.id, book: u.book, chapter: u.chapter)
        guard u.to != nil else { return all }
        return all.filter { $0.num >= u.from && $0.num <= (u.to ?? u.from) }
    }
}
