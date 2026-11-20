import SwiftUI

/// Проповеди: список; нажатие открывает редактор
struct SermonsView: View {
    @EnvironmentObject private var sermons: SermonStore
    @State private var query = ""
    @State private var openId: String?

    private var list: [Sermon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = sermons.sermons
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || ($0.series ?? "").lowercased().contains(q) || ($0.subtitle ?? "").lowercased().contains(q) }
    }

    var body: some View {
        List {
            if sermons.sermons.isEmpty {
                ContentUnavailableView {
                    Label("Нет проповедей", systemImage: "scroll")
                } description: {
                    Text("Нажмите «+» или выделите стих в чтении и выберите «В проповедь».")
                }
            }
            ForEach(list) { s in
                NavigationLink {
                    SermonEditor(id: s.id)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title.isEmpty ? "Без названия" : s.title).font(.headline)
                        HStack(spacing: 8) {
                            if let d = SermonStore.dayText(s.date) { Text(d) }
                            if let sr = s.series, !sr.isEmpty { Text("· \(sr)") }
                            Text("· блоков: \(s.blocks.count)")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Удалить", role: .destructive) { sermons.remove(s.id) }
                }
            }
        }
        .navigationTitle("Проповеди")
        .navigationBarTitleDisplayMode(.large)
        .bottomSearch($query, prompt: "Название или серия")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openId = sermons.create("Новая проповедь").id
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новая проповедь")
            }
        }
        .navigationDestination(item: $openId) { SermonEditor(id: $0) }
    }
}

/// Редактор: заголовок, дата, блоки по порядку (стих, свой текст, заметка для себя); «Кафедра»; «Поделиться»
struct SermonEditor: View {
    @EnvironmentObject private var sermons: SermonStore
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var showAddVerse = false
    @State private var editing = false
    /// «Отменить / Повторить»: снимки проповеди (до 50 шагов); правки текста, идущие подряд, — один шаг
    @State private var undo: [Sermon] = []
    @State private var redo: [Sermon] = []
    @State private var lastEdit = Date.distantPast
    /// растёт при отмене и возврате — поля текста перечитывают содержимое
    @State private var version = 0
    @State private var askDelete = false
    /// Масштаб текста в редакторе: 70–200 %, шаг 10 (ключ sermonZoom — как у Flutter-версии)
    @AppStorage("sermonZoom") private var zoom = 100
    @State private var copyId: String?
    /// после какого блока вставлять стих (nil — в конец)
    @State private var insertAfter: String?
    /// Стих добавляется над этим блоком (а не под ним)
    @State private var insertBefore: String?

    private var binding: Binding<Sermon>? {
        guard let s = sermons.get(id) else { return nil }
        return Binding(get: { sermons.get(id) ?? s }, set: { record(); sermons.upsert($0) })
    }

    private var typeSize: DynamicTypeSize {
        switch zoom {
        case ..<75: return .small
        case ..<90: return .medium
        case ..<110: return .large
        case ..<125: return .xLarge
        case ..<145: return .xxLarge
        case ..<175: return .xxxLarge
        default: return .accessibility1
        }
    }

    private func record() {
        guard let cur = sermons.get(id) else { return }
        let now = Date()
        if undo.isEmpty || now.timeIntervalSince(lastEdit) > 0.8 {
            undo.append(cur)
            if undo.count > 50 { undo.removeFirst() }
            redo.removeAll()
        }
        lastEdit = now
    }

    private func step(back: Bool) {
        guard let cur = sermons.get(id) else { return }
        if back {
            guard let p = undo.popLast() else { return }
            redo.append(cur)
            sermons.upsert(p)
        } else {
            guard let p = redo.popLast() else { return }
            undo.append(cur)
            sermons.upsert(p)
        }
        lastEdit = .distantPast
        version += 1
    }

    private func add(_ b: SermonBlock, after: String?, before: String? = nil) {
        record()
        sermons.insert([b], into: id, after: after, before: before)
    }

    /// «Добавить блок» — в конце списка, под нажатым блоком или над ним (контекстное меню)
    @ViewBuilder
    private func addMenu(after: String?, before: String? = nil) -> some View {
        Button { insertAfter = after; insertBefore = before; showAddVerse = true } label: { Label("Стих", systemImage: "book") }
        Button { add(SermonBlock(type: "text", text: ""), after: after, before: before) } label: { Label("Свой текст", systemImage: "text.alignleft") }
        Button { add(SermonBlock(type: "note", text: ""), after: after, before: before) } label: { Label("Заметка для себя", systemImage: "note.text") }
    }

    var body: some View {
        if let sb = binding {
            let s = sb.wrappedValue
            List {
                Section {
                    TextField("Название", text: sb.title)
                        .font(.headline)
                    TextField("Подзаголовок", text: Binding(get: { s.subtitle ?? "" }, set: { sb.wrappedValue.subtitle = $0 }))
                    TextField("Серия", text: Binding(get: { s.series ?? "" }, set: { sb.wrappedValue.series = $0 }))
                    DatePicker("Дата", selection: Binding(
                        get: { PlanLogic.day0(s.date ?? PlanLogic.localDate()) },
                        set: { sb.wrappedValue.date = PlanLogic.localDate($0) }
                    ), displayedComponents: .date)
                }
                Section("Блоки") {
                    ForEach(s.blocks) { b in
                        BlockRow(block: b) { updated in
                            if let i = sb.wrappedValue.blocks.firstIndex(where: { $0.id == b.id }) {
                                sb.wrappedValue.blocks[i] = updated
                            }
                        }
                        .id("\(b.id)-\(version)")
                        .contextMenu {
                            Menu {
                                addMenu(after: nil, before: b.id)
                            } label: { Label("Добавить блок выше", systemImage: "arrow.up.circle") }
                            Menu {
                                addMenu(after: b.id)
                            } label: { Label("Добавить блок ниже", systemImage: "arrow.down.circle") }
                        }
                    }
                    .onMove { from, to in sb.wrappedValue.blocks.move(fromOffsets: from, toOffset: to) }
                    .onDelete { sb.wrappedValue.blocks.remove(atOffsets: $0) }
                    Menu {
                        addMenu(after: nil, before: nil)
                    } label: {
                        Label("Добавить блок", systemImage: "plus.circle.fill")
                    }
                }
                Section {
                    Button { if let n = sermons.duplicate(id) { copyId = n } } label: { Label("Сделать копию", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { askDelete = true } label: {
                        Label { Text("Удалить проповедь") } icon: { Image(systemName: "trash") }
                    }
                    // и значок красный, не только надпись
                    .foregroundStyle(.red)
                }
            }
            .dynamicTypeSize(typeSize)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle(s.title.isEmpty ? "Проповедь" : s.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(editing ? "Готово" : "Порядок") { editing.toggle() }
                    NavigationLink {
                        PulpitView(id: id)
                    } label: {
                        Image(systemName: "text.viewfinder")
                    }
                    .accessibilityLabel("Кафедра")
                    ShareLink(item: SermonStore.text(s)) { Image(systemName: "square.and.arrow.up") }
                    Menu {
                        Button { step(back: true) } label: { Label("Отменить", systemImage: "arrow.uturn.backward") }
                            .disabled(undo.isEmpty)
                        Button { step(back: false) } label: { Label("Повторить", systemImage: "arrow.uturn.forward") }
                            .disabled(redo.isEmpty)
                        Divider()
                        Button { zoom = max(70, zoom - 10) } label: { Label("Уменьшить", systemImage: "textformat.size.smaller") }
                            .disabled(zoom <= 70)
                        Button { zoom = 100 } label: { Label("\(zoom) %", systemImage: "textformat.size") }
                        Button { zoom = min(200, zoom + 10) } label: { Label("Увеличить", systemImage: "textformat.size.larger") }
                            .disabled(zoom >= 200)
                        Divider()
                        ShareLink(item: SermonPDFFile(sermon: s), preview: SharePreview(s.title.isEmpty ? "PDF" : s.title)) {
                            Label("Печать и PDF", systemImage: "printer")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddVerse) {
                AddVerseSheet { items, moduleId in
                    record()
                    let blocks = SermonStore.versesToBlocks(items, moduleId: moduleId)
                    sermons.insert(blocks, into: id, after: insertAfter, before: insertBefore)
                }
            }
            .navigationDestination(item: $copyId) { SermonEditor(id: $0) }
            .confirmationDialog("Удалить проповедь?", isPresented: $askDelete, titleVisibility: .visible) {
                Button("Удалить проповедь", role: .destructive) {
                    sermons.remove(id)
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Проповедь удалена", systemImage: "scroll")
        }
    }
}

private struct BlockRow: View {
    let block: SermonBlock
    let onChange: (SermonBlock) -> Void
    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        switch block.type {
        case "verse":
            VStack(alignment: .leading, spacing: 6) {
                Text(SermonStore.ref(block, full: true)).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                if let tx = SermonStore.verseTexts(block), tx.count > 1, let v = block.verse {
                    ForEach(tx.indices, id: \.self) { i in
                        Text("\(v + i) \(tx[i])")
                    }
                } else {
                    Text(block.text)
                }
                ForEach((block.alt ?? []).indices, id: \.self) { i in
                    let a = (block.alt ?? [])[i]
                    Text("\(a.n ?? ""): " + (a.t ?? []).map { a.il == true ? Markup.plain($0) : $0 }.joined(separator: " "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if block.type == "note" {
                    Label("Заметка для себя (не уходит в «Поделиться»)", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField(block.type == "note" ? "Заметка" : "Свой текст: **жирный**, *курсив*", text: Binding(
                    get: { loaded ? draft : block.text },
                    set: {
                        loaded = true
                        draft = $0
                        var b = block
                        b.text = $0
                        onChange(b)
                    }
                ), axis: .vertical)
            }
        }
    }
}

/// Добавление стиха в проповедь по ссылке: «Ин 3:16», «Ин 3:16-18»; текст берётся из первого перевода
private struct AddVerseSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.dismiss) private var dismiss
    let onAdd: ([VerseItem], String) -> Void
    @State private var text = ""
    @State private var error = false

    private var module: InstalledModule? {
        store.module(panes.primaryModule) ?? store.bibles.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ин 3:16 или Ин 3:16-18", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    if error { Text("Не нашёл такое место в переводе.").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Стих в проповедь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Добавить", action: add).disabled(text.isEmpty) }
            }
        }
        .presentationDetents([.medium])
        // окно на пол-экрана — непрозрачное (в iOS 26 по умолчанию стекло, сквозь него виден текст)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func add() {
        guard let m = module, let r = RefParser.parse(text) else { error = true; return }
        let last = max(r.verse, r.endVerse ?? r.verse)
        var items: [VerseItem] = []
        for v in r.verse...min(last, r.verse + 60) {
            if let t = store.verseText(module: m.id, book: r.book, chapter: r.chapter, verse: v) {
                items.append(VerseItem(book: r.book, chapter: r.chapter, verse: v, text: t, moduleId: m.id))
            }
        }
        guard !items.isEmpty else { error = true; return }
        onAdd(items, m.id)
        dismiss()
    }
}

/// «Кафедра»: крупный текст для служения; экран не гаснет
struct PulpitView: View {
    @EnvironmentObject private var sermons: SermonStore
    let id: String
    @AppStorage("pulpitSize") private var size = 28.0

    var body: some View {
        if let s = sermons.get(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: size * 0.8) {
                    Text(s.title).font(.system(size: size * 1.2, weight: .bold))
                    ForEach(s.blocks.filter { $0.type != "note" }) { b in
                        if b.isVerse {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(SermonStore.ref(b, full: true)).font(.system(size: size * 0.7, weight: .semibold)).foregroundStyle(.tint)
                                Text(b.text).font(.system(size: size))
                            }
                        } else {
                            Text(SermonStore.formatted(b.text)).font(.system(size: size))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Кафедра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Slider(value: $size, in: 18...60, step: 2).frame(width: 200)
                }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}
