import SwiftUI

private struct LangGroup: Identifiable {
    let code: String
    let entries: [CatalogEntry]
    var id: String { code }

    var title: String {
        let name = Locale(identifier: "ru").localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Библиотека переводов: установленные (выбрать, удалить свайпом) и каталог по языкам
struct ModulesList: View {
    @EnvironmentObject private var store: ModuleStore
    @Binding var selected: String
    @State private var kind = "bible"

    private let kinds: [(String, String)] = [("bible", "Переводы"), ("dictionary", "Словари"), ("commentary", "Толкования"), ("crossrefs", "Параллельные")]

    private var shownInstalled: [InstalledModule] {
        store.installed.filter { $0.type == kind && !$0.online }
    }

    private var groups: [LangGroup] {
        let installedIds = Set(store.installed.map { $0.id })
        let list = store.catalog.filter { $0.type == kind && $0.downloadable && !installedIds.contains($0.id) }
        let by = Dictionary(grouping: list, by: { $0.language })
        return by.keys
            .sorted { a, b in
                if (a == "ru") != (b == "ru") { return a == "ru" }
                return a < b
            }
            .map { LangGroup(code: $0, entries: by[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Picker("Тип", selection: $kind) {
                    ForEach(kinds, id: \.0) { k in
                        Text(k.1).tag(k.0)
                    }
                }
                .pickerStyle(.segmented)
            }
            if !shownInstalled.isEmpty {
                Section("Установленные") {
                    ForEach(shownInstalled) { m in
                        Button {
                            if kind == "bible" { selected = m.id }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).foregroundStyle(.primary)
                                    Text(m.title).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if kind == "bible" && m.id == selected {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Удалить", role: .destructive) { store.remove(m.id) }
                        }
                    }
                }
            }
            if store.catalogLoading && store.catalog.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Загрузка каталога…").foregroundStyle(.secondary)
                    }
                }
            }
            if let e = store.catalogError {
                Section {
                    Text(e).foregroundStyle(.red)
                    Button("Повторить") { Task { await store.loadCatalog() } }
                }
            }
            ForEach(groups) { g in
                Section(g.title) {
                    ForEach(g.entries) { e in
                        row(e)
                    }
                }
            }
        }
        .task {
            if store.catalog.isEmpty { await store.loadCatalog() }
        }
    }

    private func row(_ e: CatalogEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name)
                Text(e.title).font(.subheadline).foregroundStyle(.secondary)
                if e.size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let state = store.busy[e.id] {
                ProgressView()
                Text(state).font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Скачать") {
                    Task {
                        await store.install(e)
                        if e.type == "bible" && store.module(selected) == nil { selected = e.id }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
