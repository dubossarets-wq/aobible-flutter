import SwiftUI
import UniformTypeIdentifiers

private struct LangGroup: Identifiable {
    let code: String
    let title: String
    let entries: [CatalogEntry]
    var id: String { code }
}

/// Библиотека переводов: установленные (выбрать, удалить свайпом) и каталог по языкам
struct ModulesList: View {
    @EnvironmentObject private var store: ModuleStore
    @Binding var selected: String
    @State private var kind = "bible"
    @State private var importing = false
    @State private var importError: String?
    @State private var deleting: InstalledModule?
    @State private var query = ""
    @State private var sourceText = ""
    @EnvironmentObject private var panes: PanesStore

    private let kinds: [(String, String)] = [("bible", "Переводы"), ("dictionary", "Словари"), ("commentary", "Толкования"), ("crossrefs", "Параллельные места"), ("audio", "Аудио")]

    @State private var lang = "all"

    private var shownInstalled: [InstalledModule] {
        store.allInstalled.filter { $0.type == kind && (lang == "all" || $0.language == lang) }
    }

    /// Языки модулей этого типа — установленных и из каталога
    private var languages: [String] {
        var set = Set(store.allInstalled.filter { $0.type == kind }.map { $0.language })
        for e in store.catalog where e.type == kind && e.downloadable { set.insert(e.language) }
        return set.sorted { a, b in
            if (a == "ru") != (b == "ru") { return a == "ru" }
            return langName(a) < langName(b)
        }
    }

    private func langName(_ code: String) -> String {
        // редкие языки переводов helloao системе незнакомы — тогда английское название из каталога
        let sys = Locale(identifier: "ru").localizedString(forLanguageCode: code)
        let n = (sys != nil && sys != code) ? sys! : (store.catalogLangNames[code] ?? code)
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    private var groups: [LangGroup] {
        let installedIds = Set(store.allInstalled.map { $0.id })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.catalog.filter {
            $0.type == kind && $0.downloadable && !installedIds.contains($0.id) && (lang == "all" || $0.language == lang)
                && (q.isEmpty || $0.name.lowercased().contains(q) || $0.title.lowercased().contains(q) || langName($0.language).lowercased().contains(q))
        }
        let by = Dictionary(grouping: list, by: { $0.language })
        return by.keys
            .sorted { a, b in
                if (a == "ru") != (b == "ru") { return a == "ru" }
                return a < b
            }
            .map { LangGroup(code: $0, title: langName($0), entries: by[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Picker("Тип модуля", selection: $kind) {
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
                    ForEach(shownInstalled) { m in installedRow(m) }
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
            Section {
                TextField("https://…/catalog.json", text: $sourceText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Подключить") {
                    store.setCatalogSource(sourceText)
                    Task { await store.loadCatalog() }
                }
                .disabled(sourceText.trimmingCharacters(in: .whitespaces).isEmpty)
                if !store.catalogSource.isEmpty {
                    Button("Встроенный каталог") {
                        sourceText = ""
                        store.setCatalogSource("")
                        Task { await store.loadCatalog() }
                    }
                }
                Button("Обновить список") { Task { await store.loadCatalog() } }
            } header: {
                Text("Источник каталога")
            } footer: {
                Text(store.catalogSource.isEmpty ? "Встроенный каталог" : store.catalogSource)
            }
        }
        .searchable(text: $query, prompt: "Поиск: Лопухин, Стронг, KJV…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .accessibilityLabel("Установить из файла")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .gzip, .data]) { result in
            if case .success(let url) = result {
                Task { importError = await store.importFile(url) }
            }
        }
        .confirmationDialog(
            deleting?.name ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let m = deleting { store.remove(m.id) }
                deleting = nil
            }
            Button("Отмена", role: .cancel) { deleting = nil }
        }
        .alert("Установка из файла", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
        .task {
            sourceText = store.catalogSource
            if store.catalog.isEmpty { await store.loadCatalog() }
        }
    }

    /// Установленный модуль: перевод — выбор и звёздочка «основной»; остальные — переключатель «включён»;
    /// «Обновить», когда в каталоге версия новее
    private func installedRow(_ m: InstalledModule) -> some View {
        let isBible = kind == "bible"
        let on = store.isEnabled(m.id)
        let primary = panes.primaryModule == m.id
        return HStack {
            Button {
                if isBible { selected = m.id }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).foregroundStyle(.primary)
                        Text(m.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if isBible && m.id == selected {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let state = store.busy[m.id] {
                ProgressView()
                Text(state).font(.caption).foregroundStyle(.secondary)
            } else if store.hasUpdate(m), let e = store.catalogEntry(m.id) {
                Button("Обновить") { Task { await store.install(e) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if isBible {
                Button {
                    panes.setExplicitPrimary(m.id)
                } label: {
                    Image(systemName: primary ? "star.fill" : "star")
                        .foregroundStyle(primary ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primary ? "Основной перевод" : "Сделать основным")
            } else {
                Toggle("", isOn: Binding(get: { on }, set: { store.setEnabled(m.id, $0) }))
                    .labelsHidden()
            }
        }
        .opacity(isBible || on ? 1 : 0.5)
        .swipeActions {
            Button("Удалить", role: .destructive) { deleting = m }
        }
        .contextMenu {
            if let e = store.catalogEntry(m.id), e.downloadable {
                Button { Task { await store.install(e) } } label: { Label("Переустановить", systemImage: "arrow.clockwise") }
            }
            Button(role: .destructive) { deleting = m } label: { Label("Удалить", systemImage: "trash") }
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
