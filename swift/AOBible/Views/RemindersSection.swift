import SwiftUI

/// «Напоминать о чтении»: переключатель и список напоминаний — обычных (уведомление) и будильников
struct RemindersSection: View {
    @EnvironmentObject private var plans: PlansStore
    let flash: (String) -> Void
    @State private var d = Reminders.data

    private let repeats: [(Int, String)] = [
        (0, "Один раз"), (30, "Каждые 30 мин"), (60, "Каждый час"), (120, "Каждые 2 ч"),
        (180, "Каждые 3 ч"), (240, "Каждые 4 ч"), (360, "Каждые 6 ч"),
    ]
    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        Section {
            Toggle("Напоминать о чтении", isOn: Binding(get: { d.on }, set: { setOn($0) }))
            if d.on {
                ForEach(d.list.indices, id: \.self) { i in card(i) }
                HStack(spacing: 16) {
                    Button { add(alarm: false) } label: { Label("Добавить напоминание", systemImage: "plus") }
                    Spacer()
                    Button { add(alarm: true) } label: { Label("Добавить будильник", systemImage: "alarm") }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        } footer: {
            if d.on {
                Text("Напоминание — уведомление с отрывками на сегодня. Будильник звонит, как обычный, даже когда телефон в беззвучном режиме.")
            }
        }
    }

    // MARK: - Карточка напоминания

    @ViewBuilder private func card(_ i: Int) -> some View {
        let r = d.list[i]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DatePicker("", selection: timeBinding(i, \.time), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                if r.every > 0 {
                    Text("–").foregroundStyle(.secondary)
                    DatePicker("", selection: timeBinding(i, \.until), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Spacer()
                Button {
                    toggleKind(i)
                } label: {
                    Label(r.isAlarm ? "Будильник" : "Напоминание", systemImage: r.isAlarm ? "alarm.fill" : "bell.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(r.isAlarm ? Color.orange.opacity(0.18) : Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(r.isAlarm ? Color.orange : Color.accentColor)
                }
                .buttonStyle(.plain)
                if d.list.count > 1 {
                    Button {
                        d.list.remove(at: i)
                        save()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить напоминание")
                }
            }
            HStack {
                Text("Повтор").foregroundStyle(.secondary)
                Spacer()
                Picker("Повтор", selection: Binding(get: { r.every }, set: { d.list[i].every = $0; save() })) {
                    ForEach(repeats, id: \.0) { Text(LocalizedStringKey($0.1)).tag($0.0) }
                }
                .labelsHidden()
            }
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { wd in
                    let on = r.days.isEmpty || r.days.contains(wd)
                    Button {
                        toggleDay(i, wd)
                    } label: {
                        Text(LocalizedStringKey(weekdays[wd - 1]))
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(on ? Color.accentColor.opacity(r.days.isEmpty ? 0.14 : 1) : Color.secondary.opacity(0.14), in: Capsule())
                            .foregroundStyle(on ? (r.days.isEmpty ? Color.accentColor : Color.white) : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Действия

    private func timeBinding(_ i: Int, _ kp: WritableKeyPath<ReminderItem, String>) -> Binding<Date> {
        Binding(
            get: {
                let p = d.list[i][keyPath: kp].split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(from: DateComponents(hour: p.first ?? 8, minute: p.count > 1 ? p[1] : 0)) ?? Date()
            },
            set: { t in
                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                d.list[i][keyPath: kp] = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
                save()
            }
        )
    }

    private func toggleDay(_ i: Int, _ wd: Int) {
        var set = Set(d.list[i].days.isEmpty ? Array(1...7) : d.list[i].days)
        if set.contains(wd) {
            if set.count == 1 { return } // последний день выключить нельзя
            set.remove(wd)
        } else {
            set.insert(wd)
        }
        d.list[i].days = set.count == 7 ? [] : set.sorted()
        save()
    }

    private func add(alarm: Bool) {
        let last = d.list.last
        let base = last.map { $0.every > 0 ? $0.until : $0.time } ?? "07:00"
        let p = base.split(separator: ":").compactMap { Int($0) }
        let h = min(23, (p.first ?? 6) + 1)
        let t = String(format: "%02d:%02d", h, p.count > 1 ? p[1] : 0)
        let item = ReminderItem(time: t, every: 0, until: "20:00", days: [], alarm: alarm)
        d.list.append(item)
        if alarm { Task { await ensureAlarmAccess(item.id) } }
        save()
    }

    private func toggleKind(_ i: Int) {
        let was = d.list[i].isAlarm
        d.list[i].alarm = was ? nil : true
        save()
        if !was { Task { await ensureAlarmAccess(d.list[i].id) } }
    }

    /// Будильнику нужно разрешение «Будильники и таймеры»; без него напоминание остаётся громким уведомлением
    private func ensureAlarmAccess(_ id: String) async {
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
