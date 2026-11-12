import SwiftUI

/// «Ещё» → «История»: все места, где человек читал, по дням (сегодня, вчера, дальше по датам).
/// Сверху выбор: всё / один день / один месяц; стрелками — соседний день или месяц, где что-то читалось.
/// Нажатие открывает место, смахивание влево удаляет запись (с «Отменить»)
struct HistoryView: View {
    @EnvironmentObject private var panes: PanesStore

    var body: some View {
        HistoryList(log: panes.log)
    }
}

private struct DayGroup: Identifiable {
    let day: Date
    var items: [HistoryEntry]
    var id: Date { day }
}

private struct HistoryList: View {
    @ObservedObject var log: ReadingHistory
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.openVerse) private var openVerse
    @Environment(\.locale) private var locale

    enum Mode: Hashable { case all, day, month }

    @State private var mode = Mode.all
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var month = HistoryList.monthStart(Date())
    @State private var confirmClear = false
    @State private var undo: [HistoryEntry]?

    private var cal: Calendar { Calendar.current }

    static func monthStart(_ d: Date) -> Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? c.startOfDay(for: d)
    }

    // MARK: - Данные

    /// Новые сверху, с учётом выбранного дня или месяца
    private var filtered: [HistoryEntry] {
        let list = log.items.reversed()
        switch mode {
        case .all: return Array(list)
        case .day: return list.filter { cal.isDate($0.time, inSameDayAs: day) }
        case .month: return list.filter { cal.isDate($0.time, equalTo: month, toGranularity: .month) }
        }
    }

    private var groups: [DayGroup] {
        var out: [DayGroup] = []
        for e in filtered {
            let d = cal.startOfDay(for: e.time)
            if let last = out.last, last.day == d {
                out[out.count - 1].items.append(e)
            } else {
                out.append(DayGroup(day: d, items: [e]))
            }
        }
        return out
    }

    /// Дни, когда что-то читалось, новые первыми
    private var days: [Date] {
        var seen = Set<Date>()
        var out: [Date] = []
        for e in log.items.reversed() {
            let d = cal.startOfDay(for: e.time)
            if seen.insert(d).inserted { out.append(d) }
        }
        return out
    }

    private var months: [Date] {
        var seen = Set<Date>()
        var out: [Date] = []
        for e in log.items.reversed() {
            let m = Self.monthStart(e.time)
            if seen.insert(m).inserted { out.append(m) }
        }
        return out
    }

    private func bookName(_ book: String) -> String {
        let m = store.module(panes.primaryModule) ?? store.bibles.first
        return m?.books.first { $0.id == book }?.name ?? Books.info(book)?.name ?? book
    }

    private func title(_ e: HistoryEntry) -> String {
        e.verse > 0 ? "\(bookName(e.book)) \(e.chapter):\(e.verse)" : "\(bookName(e.book)) \(e.chapter)"
    }

    private func preview(_ e: HistoryEntry) -> String? {
        let t = store.verseText(module: panes.primaryModule, book: e.book, chapter: e.chapter, verse: max(e.verse, 1))
        guard let t, !t.isEmpty else { return nil }
        return String(t.prefix(140))
    }

    private func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(locale: locale).hour().minute())
    }

    private func dayTitle(_ d: Date) -> String {
        if cal.isDateInToday(d) { return String(localized: "Сегодня") }
        if cal.isDateInYesterday(d) { return String(localized: "Вчера") }
        var f = Date.FormatStyle(locale: locale).weekday(.wide).day().month(.wide)
        if !cal.isDate(d, equalTo: Date(), toGranularity: .year) { f = f.year() }
        return d.formatted(f).capitalizedFirst
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return f.string(from: d).capitalizedFirst
    }

    // MARK: - Вид

    var body: some View {
        List {
            // переключатель — сам по себе, без карточки; день или месяц — своей карточкой под ним
            Section {
                Picker("Показать", selection: $mode) {
                    Text("Всё").tag(Mode.all)
                    Text("День").tag(Mode.day)
                    Text("Месяц").tag(Mode.month)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            if mode != .all {
                Section {
                    if mode == .day { dayBar } else { monthBar }
                }
            }
            if groups.isEmpty {
                Section {
                    empty.listRowBackground(Color.clear)
                }
            }
            ForEach(groups) { g in
                Section {
                    ForEach(g.items) { e in row(e) }
                } header: {
                    Text(dayTitle(g.day))
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .confirmationDialog(clearQuestion, isPresented: $confirmClear, titleVisibility: .visible) {
            Button(clearButton, role: .destructive) { clearShown() }
            Button("Отмена", role: .cancel) {}
        }
        .overlay(alignment: .bottom) { undoBar }
        .animation(.default, value: undo?.count)
        .onAppear {
            if let d = days.first { day = d }
            if let m = months.first { month = m }
        }
    }

    @ViewBuilder private var empty: some View {
        ContentUnavailableView {
            Label("История пуста", systemImage: "clock")
        } description: {
            Text(mode == .all ? "Здесь появятся места, которые вы читали." : "В этот период вы не читали.")
        }
    }

    private func row(_ e: HistoryEntry) -> some View {
        Button {
            openVerse(e.book, e.chapter, e.verse)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(e)).foregroundStyle(.primary)
                    if let t = preview(e) {
                        Text(t).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(time(e.time)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Удалить", role: .destructive) {
                log.remove([e.id])
                undo = [e]
            }
        }
    }

    // MARK: - День и месяц

    private var dayBar: some View {
        let today = cal.startOfDay(for: Date())
        let prev = days.first { $0 < day }
        let next = days.last { $0 > day }
        return HStack {
            Button {
                if let prev { day = prev }
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .disabled(prev == nil)
            Spacer()
            DatePicker("День", selection: Binding(get: { day }, set: { day = cal.startOfDay(for: $0) }),
                       in: ...today, displayedComponents: .date)
                .labelsHidden()
            Spacer()
            Button {
                if let next { day = next }
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled(next == nil)
        }
        .buttonStyle(.borderless)
        .font(.body.weight(.semibold))
    }

    private var monthBar: some View {
        let list = months.isEmpty ? [month] : months
        let i = list.firstIndex(of: month)
        let prev: Date? = i.flatMap { $0 + 1 < list.count ? list[$0 + 1] : nil }
        let next: Date? = i.flatMap { $0 > 0 ? list[$0 - 1] : nil }
        return HStack {
            Button {
                if let prev { month = prev }
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .disabled(prev == nil)
            Spacer()
            Menu {
                Picker("Месяц", selection: $month) {
                    ForEach(list, id: \.self) { m in Text(monthTitle(m)).tag(m) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(monthTitle(month))
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }
            Spacer()
            Button {
                if let next { month = next }
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled(next == nil)
        }
        .buttonStyle(.borderless)
        .font(.body.weight(.semibold))
    }

    // MARK: - Очистка

    private var clearQuestion: String {
        switch mode {
        case .all: return String(localized: "Очистить всю историю?")
        case .day: return String(localized: "Удалить историю за \(dayTitle(day).lowercased())?")
        case .month: return String(localized: "Удалить историю за \(monthTitle(month).lowercased())?")
        }
    }

    private var clearButton: String {
        mode == .all ? String(localized: "Очистить историю") : String(localized: "Удалить")
    }

    private func clearShown() {
        let shown = filtered
        guard !shown.isEmpty else { return }
        log.remove(Set(shown.map(\.id)))
        undo = shown
    }

    @ViewBuilder private var undoBar: some View {
        if let u = undo {
            HStack(spacing: 14) {
                Text(u.count == 1 ? String(localized: "Запись удалена") : String(localized: "Удалено записей: \(u.count)"))
                    .font(.subheadline)
                Button("Отменить") {
                    log.restore(u)
                    undo = nil
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: u.map(\.id)) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { undo = nil }
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}
