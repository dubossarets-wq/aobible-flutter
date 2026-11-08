import SwiftUI
import UniformTypeIdentifiers

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
    @State private var importing = false
    @State private var importError: String?

    private let kinds: [(String, String)] = [("bible", "Переводы"), ("dictionary", "Словари"), ("commentary", "Толкования"), ("crossrefs", "Параллельные места"), ("audio", "Аудио")]

    @State private var lang = "all"

    private var shownInstalled: [InstalledModule] {
        store.installed.filter { $0.type == kind && !$0.online && (lang == "all" || $0.language == lang) }
    }

    /// Языки модулей этого типа — установленных и из каталога
    private var languages: [String] {
        var set = Set(store.installed.filter { $0.type == kind }.map { $0.language })
        for e in store.catalog where e.type == kind && e.downloadable { set.insert(e.language) }
        return set.sorted { a, b in
            if (a == "ru") != (b == "ru") { return a == "ru" }
            return langName(a) < langName(b)
        }
    }

    private func langName(_ code: String) -> String {
        let n = Locale(identifier: "ru").localizedString(forLanguageCode: code) ?? code
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    private var groups: [LangGroup] {
        let installedIds = Set(store.installed.map { $0.id })
        let list = store.catalog.filter { $0.type == kind && $0.downloadable && !installedIds.contains($0.id) && (lang == "all" || $0.language == lang) }
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
                        Text(LocalizedStringKey(k.1)).tag(k.0)
                    }
                }
                .pickerStyle(.menu)
                Picker("Язык модуля", selection: $lang) {
                    Text("Все языки").tag("all")
                    ForEach(languages, id: \.self) { l in
                        Text(langName(l)).tag(l)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: kind) { _, _ in lang = "all" }
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
                        .buttonStyle(.plain)
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .accessibilityLabel("Установить из файла")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .gzip, .data]) { result in
            if case .success(let url) = result {
                Task { importError = await store.importFile(url) }
            }
        }
        .alert("Установка из файла", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
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
