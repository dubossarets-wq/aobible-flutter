import SwiftUI

/// «Напоминать о чтении» — как «Будильники» в «Часах»: главный переключатель, список напоминаний (крупное время,
/// под ним вид и дни, у каждого свой переключатель), нажатие открывает настройку. Дни — по неделе или по календарю
/// (конкретные даты — для сменного графика)
struct RemindersSection: View {
    @EnvironmentObject private var plans: PlansStore
    let flash: (String) -> Void
    @State private var d = Reminders.data
    @State private var editing: ReminderDraft?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { d.on }, set: { setOn($0) })) {
                Label {
                    Text("Напоминать о чтении")
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .sheet(item: $editing) { e in
                ReminderEditor(draft: e.item, isNew: e.isNew, canDelete: d.list.count > 1) { saved in
                    commit(saved, isNew: e.isNew)
                } onDelete: {
                    remove(e.item.id)
                }
            }
            if d.on {
                ForEach(d.list) { r in row(r) }
                Button {
                    editing = ReminderDraft(item: newItem(), isNew: true)
                } label: {
                    Label("Добавить напоминание", systemImage: "plus")
                }
            }
        } header: {
            Text("Напоминания")
        } footer: {
            if d.on {
                Text("Напоминание — уведомление с отрывками планов на этот день. Будильник звонит, даже когда телефон в беззвучном режиме.")
            }
        }
    }

    // MARK: - Строка напоминания

    private func row(_ r: ReminderItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ReminderText.time(r))
                    .font(.system(size: r.every > 0 ? 30 : 40, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: r.isAlarm ? "alarm.fill" : "bell.fill")
                        .foregroundStyle(r.isAlarm ? Color.orange : Color.accentColor)
                    Text(ReminderText.summary(r))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .font(.subheadline)
            }
            .opacity(r.isOn ? 1 : 0.45)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { r.isOn }, set: { on in setItem(r.id) { $0.off = on ? nil : true } }))
                .labelsHidden()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { editing = ReminderDraft(item: r, isNew: false) }
        .swipeActions {
            if d.list.count > 1 {
                Button("Удалить", role: .destructive) { remove(r.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть настройку")
    }

    // MARK: - Действия

    private func newItem() -> ReminderItem {
        let last = d.list.last
        let base = last.map { $0.every > 0 ? $0.until : $0.time } ?? "07:00"
        let p = base.split(separator: ":").compactMap { Int($0) }
        let h = min(23, (p.first ?? 6) + 1)
        return ReminderItem(time: String(format: "%02d:%02d", h, p.count > 1 ? p[1] : 0), every: 0, until: "20:00", days: [])
    }

    private func setItem(_ id: String, _ change: (inout ReminderItem) -> Void) {
        guard let i = d.list.firstIndex(where: { $0.id == id }) else { return }
        change(&d.list[i])
        save()
    }

    private func commit(_ r: ReminderItem, isNew: Bool) {
        if isNew {
            d.list.append(r)
        } else if let i = d.list.firstIndex(where: { $0.id == r.id }) {
            let wasAlarm = d.list[i].isAlarm
            d.list[i] = r
            if wasAlarm { save(); return }
        }
        save()
        if r.isAlarm { Task { await ensureAlarmAccess() } }
    }

    private func remove(_ id: String) {
        guard d.list.count > 1 else { return }
        d.list.removeAll { $0.id == id }
        save()
    }

    /// Будильнику нужно разрешение «Будильники и таймеры»; без него напоминание остаётся громким уведомлением
    private func ensureAlarmAccess() async {
        if await Reminders.requestAlarmAccess() { return }
        flash("Будильники запрещены — разрешите их в настройках телефона. Пока придёт громкое уведомление.")
        Reminders.schedule(plans.plans)
    }

    private func setOn(_ on: Bool) {
        if on {
            Task {
                let ok = await Reminders.requestAccess()
                if !ok {
                    flash("Уведомления запрещены — разрешите их в настройках телефона")
                    return
                }
                d.on = true
                save()
                if d.list.count == 1, d.list[0].every == 0 {
                    flash("Напомню в \(d.list[0].time)")
                } else {
                    flash("Напоминания включены")
                }
                if d.list.contains(where: { $0.isAlarm }) { _ = await Reminders.requestAlarmAccess() }
            }
        } else {
            d.on = false
            save()
        }
    }

    private func save() {
        Reminders.data = d
        Reminders.schedule(plans.plans)
    }
}

struct ReminderDraft: Identifiable {
    var id: String { item.id }
    let item: ReminderItem
    let isNew: Bool
}

/// Подписи напоминания: время и «Будни · каждый час»
enum ReminderText {
    static let repeats: [(Int, String)] = [
        (0, "Нет"), (30, "Каждые 30 мин"), (60, "Каждый час"), (120, "Каждые 2 ч"),
        (180, "Каждые 3 ч"), (240, "Каждые 4 ч"), (360, "Каждые 6 ч"),
    ]
    static let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    static func time(_ r: ReminderItem) -> String {
        r.every > 0 ? "\(r.time)–\(r.until)" : r.time
    }

    static func days(_ r: ReminderItem) -> String {
        if let ds = r.dates, !ds.isEmpty {
            let today = ReminderItem.dayKey(Date())
            let next = ds.filter { $0 >= today }.sorted()
            guard let first = next.first else { return "Отмеченные даты прошли" }
            if next.count == 1 { return "Только \(short(first))" }
            return "По календарю: \(next.count) \(plural(next.count)), ближайший — \(short(first))"
        }
        let s = Set(r.days)
        if s.isEmpty || s.count == 7 { return "Каждый день" }
        if s == [1, 2, 3, 4, 5] { return "По будням" }
        if s == [6, 7] { return "По выходным" }
        return r.days.sorted().map { weekdays[$0 - 1] }.joined(separator: ", ")
    }

    static func summary(_ r: ReminderItem) -> String {
        var parts = [days(r)]
        if r.every > 0, let t = repeats.first(where: { $0.0 == r.every })?.1 { parts.append(t.lowercased()) }
        return parts.joined(separator: " · ")
    }

    /// «18 нояб.»
    static func short(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return key }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private static func plural(_ n: Int) -> String {
        let a = n % 10, b = n % 100
        if a == 1 && b != 11 { return "день" }
        if (2...4).contains(a) && !(12...14).contains(b) { return "дня" }
        return "дней"
    }
}

/// Настройка напоминания: время колесом, вид (напоминание или будильник), повтор в течение дня, дни недели или
/// даты в календаре; «Готово» сохраняет
struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: ReminderItem
    /// 0 — по дням недели, 1 — по календарю
    @State private var mode: Int
    @State private var picked: Set<DateComponents>
    let isNew: Bool
    let canDelete: Bool
    let onSave: (ReminderItem) -> Void
    let onDelete: () -> Void

    init(draft: ReminderItem, isNew: Bool, canDelete: Bool, onSave: @escaping (ReminderItem) -> Void, onDelete: @escaping () -> Void) {
        _item = State(initialValue: draft)
        _mode = State(initialValue: draft.byCalendar ? 1 : 0)
        _picked = State(initialValue: Set((draft.dates ?? []).compactMap(Self.comps)))
        self.isNew = isNew
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private static let cal = Calendar.current

    private static func comps(_ key: String) -> DateComponents? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return cal.dateComponents([.calendar, .era, .year, .month, .day], from: date)
    }

    private static func key(_ c: DateComponents) -> String? {
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func timeBinding(_ kp: WritableKeyPath<ReminderItem, String>) -> Binding<Date> {
        Binding(
            get: {
                let p = item[keyPath: kp].split(separator: ":").compactMap { Int($0) }
                return Self.cal.date(from: DateComponents(hour: p.first ?? 8, minute: p.count > 1 ? p[1] : 0)) ?? Date()
            },
            set: { t in
                let c = Self.cal.dateComponents([.hour, .minute], from: t)
                item[keyPath: kp] = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
            }
        )
    }

    private var canSave: Bool { mode == 0 || !picked.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Время", selection: timeBinding(\.time), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section {
                    CapsuleSwitcher(
                        options: [(false, Text("Напоминание")), (true, Text("Будильник"))],
                        selection: Binding(get: { item.isAlarm }, set: { item.alarm = $0 ? true : nil })
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                } footer: {
                    Text(item.isAlarm
                         ? "Звонит, как будильник «Часов», даже в беззвучном режиме и в «Фокусе»."
                         : "Тихое уведомление со списком отрывков на этот день.")
                }

                Section("В течение дня") {
                    Picker("Повторять", selection: $item.every) {
                        ForEach(ReminderText.repeats, id: \.0) { Text(LocalizedStringKey($0.1)).tag($0.0) }
                    }
                    if item.every > 0 {
                        DatePicker("До", selection: timeBinding(\.until), displayedComponents: .hourAndMinute)
                    }
                }

                // переключатель — отдельно над карточкой (внутри карточки он срезал её верхние углы)
                Section {
                    CapsuleSwitcher(options: [(0, Text("Дни недели")), (1, Text("Календарь"))], selection: $mode.animation())
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                } header: {
                    Text("Когда напоминать")
                }

                Section {
                    if mode == 0 {
                        weekdays
                    } else {
                        MultiDatePicker("Даты", selection: $picked, in: Self.cal.startOfDay(for: Date())...)
                        if !picked.isEmpty {
                            Button("Снять все даты", role: .destructive) { picked = [] }
                        }
                    }
                } footer: {
                    if mode == 1 {
                        Text(picked.isEmpty
                             ? "Отметьте дни, когда напоминать, — удобно при сменном графике."
                             : "Отмечено: \(picked.count). Напоминание сработает только в эти дни.")
                    }
                }

                if !isNew && canDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Удалить напоминание").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            // секции ближе друг к другу: переключатель и его карточка — одна группа
            .listSectionSpacing(.compact)
            .navigationTitle(isNew ? "Новое напоминание" : "Напоминание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отмена")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        var r = item
                        r.dates = mode == 1 ? picked.compactMap(Self.key).sorted() : nil
                        if r.dates?.isEmpty == true { r.dates = nil }
                        onSave(r)
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .disabled(!canSave)
                        .accessibilityLabel("Готово")
                }
            }
        }
        .presentationDetents([.large])
        // Непрозрачный фон — внутри окна, а не presentationBackground: со своим presentationBackground система в iOS 26 не растягивает окно плавно из «парящего» вида на всю ширину (поднимается, а ширина прибавляется рывком)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    /// Дни недели кружками: все включены — «каждый день»; последний выключить нельзя
    private var weekdays: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { wd in
                let on = item.days.isEmpty || item.days.contains(wd)
                Button {
                    var set = Set(item.days.isEmpty ? Array(1...7) : item.days)
                    if set.contains(wd) {
                        if set.count == 1 { return }
                        set.remove(wd)
                    } else {
                        set.insert(wd)
                    }
                    item.days = set.count == 7 ? [] : set.sorted()
                } label: {
                    Text(LocalizedStringKey(ReminderText.weekdays[wd - 1]))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
