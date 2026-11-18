import SwiftUI

/// Быстрое окно выбора перевода: только установленные переводы (открывается сразу, без каталога из тысячи строк).
/// Избранные — наверху (звёздочкой можно отметить несколько), выбранный подсвечен плашкой цвета акцента.
/// Каталог для скачивания лежит на следующем экране и строится, только когда его открыли
struct TranslationPicker: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    let current: String
    /// Выбрали перевод (окно закрывает вызывающий)
    let onPick: (String) -> Void

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
            }
        }
        .animation(.snappy(duration: 0.3), value: panes.favorites)
        .sensoryFeedback(.selection, trigger: panes.favorites)
    }

    private func row(_ m: InstalledModule) -> some View {
        let isCurrent = m.id == current
        let fav = panes.isFavorite(m.id)
        return HStack(spacing: 12) {
            Button {
                onPick(m.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.name)
                            .font(.body.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        if panes.primaryModule == m.id {
                            Text("основной")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.18), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(m.title)
                        .font(.subheadline)
                        .foregroundStyle(isCurrent ? Color.accentColor.opacity(0.8) : Color.secondary)
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
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground))
                .padding(.horizontal, isCurrent ? 6 : 0)
                .padding(.vertical, isCurrent ? 2 : 0)
        )
        .contextMenu {
            Button { panes.toggleFavorite(m.id) } label: {
                Label(fav ? "Убрать из избранного" : "В избранное", systemImage: fav ? "star.slash" : "star")
            }
            Button {
                panes.setExplicitPrimary(m.id)
                if !fav { panes.toggleFavorite(m.id) }
            } label: { Label("Сделать основным", systemImage: "bookmark") }
        }
    }
}
