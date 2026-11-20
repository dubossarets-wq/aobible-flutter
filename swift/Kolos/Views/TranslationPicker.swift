import SwiftUI

/// Быстрое окно выбора перевода: только установленные переводы (открывается сразу, без каталога из тысячи строк).
/// Избранные — наверху (звёздочкой можно отметить несколько), выбранный подсвечен плашкой цвета акцента.
/// Каталог для скачивания лежит на следующем экране и строится, только когда его открыли
struct TranslationPicker: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    let current: String
    /// Переводы, открытые сейчас во всех окнах (параллельное чтение) — тоже голубые
    var active: Set<String> = []
    /// Выбрали перевод (окно закрывает вызывающий)
    let onPick: (String) -> Void
    /// Перевод, который спрашиваем удалить
    @State private var deleting: InstalledModule?

    private var bibles: [InstalledModule] { store.bibles }

    private var favs: [InstalledModule] {
        let all = bibles
        return panes.favorites.compactMap { id in all.first { $0.id == id } }
    }

    private var others: [InstalledModule] {
        let f = Set(panes.favorites)
        return bibles.filter { !f.contains($0.id) }
    }

    var body: some View {
        List {
            if !favs.isEmpty {
                Section("Избранные") {
                    ForEach(favs) { row($0) }
                }
            }
            Section(favs.isEmpty ? "Переводы" : "Остальные") {
                ForEach(others) { row($0) }
            }
            Section {
                NavigationLink {
                    ModulesList(selected: Binding(get: { current }, set: { onPick($0) }))
                        .navigationTitle("Библиотека")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Скачать другие переводы", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Звёздочкой отметьте любимые переводы — они всегда наверху. Можно выбрать несколько.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        // как библиотека модулей: карточки со скруглёнными краями на сером фоне
        .listStyle(.insetGrouped)
        .animation(.snappy(duration: 0.3), value: panes.favorites)
        .sensoryFeedback(.selection, trigger: panes.favorites)
        .confirmationDialog(
            deleting.map { "Удалить «\($0.name)»?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let m = deleting {
                    if panes.isFavorite(m.id) { panes.toggleFavorite(m.id) }
                    store.remove(m.id)
                }
                deleting = nil
            }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: {
            Text("Перевод можно будет снова скачать в библиотеке.")
        }
    }

    private func row(_ m: InstalledModule) -> some View {
        let isCurrent = m.id == current
        let isActive = isCurrent || active.contains(m.id)
        let fav = panes.isFavorite(m.id)
        return HStack(spacing: 12) {
            Button {
                onPick(m.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.name)
                            .font(.body.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    }
                    Text(m.title)
                        .font(.subheadline)
                        .foregroundStyle(isActive ? Color.accentColor.opacity(0.8) : Color.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                panes.toggleFavorite(m.id)
            } label: {
                Image(systemName: fav ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(fav ? Color.yellow : Color.secondary.opacity(0.7))
                    .symbolEffect(.bounce, value: fav)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(fav ? "Убрать из избранного" : "В избранное")
        }
        // выбранный перевод — как в библиотеке модулей: название цветом акцента, без плашки
        .contextMenu {
            Button { panes.toggleFavorite(m.id) } label: {
                Label(fav ? "Убрать из избранного" : "В избранное", systemImage: fav ? "star.slash" : "star")
            }
            // последний перевод не удаляется — читать было бы нечего
            if bibles.count > 1 {
                Button(role: .destructive) { deleting = m } label: { Label("Удалить", systemImage: "trash") }
            }
        }
        .swipeActions {
            if bibles.count > 1 {
                Button("Удалить", role: .destructive) { deleting = m }
            }
        }
    }
}
