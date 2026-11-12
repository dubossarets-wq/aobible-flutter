import SwiftUI

// Окно словарной статьи — как во Flutter-версии (dictionary_sheet.dart): «Слово: …» и стих в шапке, вкладки словарей,
// статья Стронга (лемма, транслитерация, номер, язык, «В этом стихе», «Значение», «Происхождение», толковые словари,
// «В Синодальном переводе», «Где встречается» со статистикой и «Все места»), статья словаря «по словам».

/// Слово оригинала, которому соответствует нажатое слово
struct OrigInfo {
    let orig: String
    let morph: String?
    let num: String?
}

struct DictRequest: Identifiable {
    let id = UUID()
    let text: String
    let strongs: [String]
    let morph: [String]
    let book: String
    let chapter: Int
    let verse: Int
    /// словарь и статья, выбранные в списке у слова
    var preselect: (moduleId: String, key: String)? = nil
    /// сразу статья первого словаря Стронга (нажали на номер)
    var autoOpen = false
    var origWord: OrigInfo? = nil
    /// номер слова в стихе RST+ (для формы слова в оригинале)
    var wordIndex: Int? = nil
}

/// Русское множественное число: 1 стих, 2 стиха, 5 стихов
func ruPlural(_ n: Int, _ forms: [String]) -> String {
    let a = n % 10, b = n % 100
    let i = (a == 1 && b != 11) ? 0 : ((2...4).contains(a) && !(12...14).contains(b)) ? 1 : 2
    return forms[min(i, forms.count - 1)]
}

/// «Быт. 2:20»
func shortRef(_ book: String, _ chapter: Int, _ verse: Int) -> String {
    "\(Books.info(book)?.short ?? book) \(chapter):\(verse)"
}

struct DictionarySheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var pal
    let req: DictRequest
    /// открыть место (закрывает окна)
    var onOpenRef: (String, Int, Int) -> Void

    private enum Layer {
        case strong(String, [ModResult])
        case word(InstalledModule, Found)
    }

    @State private var res: LookupResult?
    @State private var selected: String?
    @State private var entryIdx = 0
    @State private var stack: [Layer] = []
    @State private var orig: OrigInfo?
    @State private var path: [String] = []
    @State private var detent: PresentationDetent = .large

    private var subtitle: String { shortRef(req.book, req.chapter, req.verse) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { num in
                ConcordanceView(num: num, lemma: lemmaFor(num), onOpenRef: onOpenRef)
            }
        }
        .tint(pal.accent)
        .presentationBackground(Color(.systemGroupedBackground))
        // два положения: во всю высоту и маленькое (без среднего), затем — закрыть
        .presentationDetents([.height(200), .large], selection: $detent)
        .task {
            guard res == nil else { return }
            await Task.yield()
            load()
        }
    }

    // MARK: - Данные

    private func load() {
        let r = Lexicon.lookupWord(store: store, text: req.text, strongs: req.strongs, morph: req.morph, book: req.book)
        if let pre = req.preselect {
            selected = pre.moduleId
            if let found = r.results.first(where: { $0.module.id == pre.moduleId })?.found,
               let i = found.firstIndex(where: { $0.key == pre.key }) { entryIdx = i }
        } else if req.autoOpen {
            selected = r.results.first { $0.module.dictionaryKind == "strongs" }?.module.id
        }
        // слово оригинала: из подстрочника; нажатое слово само греческое/еврейское; по порядку слова в стихе RST+
        if let o = req.origWord {
            orig = o
        } else if !req.strongs.isEmpty, req.text.range(of: "[\\u0370-\\u03FF\\u1F00-\\u1FFF\\u0590-\\u05FF]", options: .regularExpression) != nil {
            let w = req.text.replacingOccurrences(of: "[.,;:·!?»«“”()\\[\\]]+$", with: "", options: .regularExpression)
            orig = OrigInfo(orig: w, morph: req.morph.first, num: Align.strongNum(req.strongs[0]))
        } else if let wi = req.wordIndex, let ws = Align.ruWords(store: store, book: req.book, chapter: req.chapter, verse: req.verse), wi < ws.count, !ws[wi].orig.isEmpty {
            orig = OrigInfo(orig: ws[wi].orig, morph: ws[wi].origMorph, num: ws[wi].num)
        }
        res = r
    }

    private func lemmaFor(_ num: String) -> String? {
        for d in store.dictionaries where d.dictionaryKind == "strongs" {
            if let l = store.dictEntry(module: d, key: num)?["lemma"] as? String, !l.isEmpty { return l }
        }
        return nil
    }

    private func openStrong(_ num: String) {
        let r = Lexicon.lookupStrong(store: store, num: num)
        guard !r.isEmpty else { return }
        stack.append(.strong(num, r))
        entryIdx = 0
    }

    /// «См. Законник» — статья этого слова в том же словаре
    private func openSee(_ module: InstalledModule, _ word: String) {
        let keys = [Lexicon.dictKey(word), word.lowercased()]
        if let f = store.dictGetMany(module: module, keys: keys).first {
            stack.append(.word(module, Found(key: f.0, entry: f.1, match: "form")))
        }
    }

    private var backAction: (() -> Void)? {
        if !stack.isEmpty { return { stack.removeLast() } }
        if selected != nil, !(req.autoOpen && res?.results.count == 1) { return { selected = nil } }
        return nil
    }

    // MARK: - Шапка

    private var header: some View {
        let title: String = {
            if case .strong(let num, _)? = stack.last { return "Статья \(num)" }
            return "Слово: \(req.text)"
        }()
        return SheetHeader(title: title, subtitle: subtitle, onBack: backAction) { dismiss() }
    }

    // MARK: - Содержимое

    @ViewBuilder private var content: some View {
        if let res {
            switch stack.last {
            case .strong(let num, let results)?:
                if let m = results.first {
                    StrongEntryView(num: num, entry: m.found[0].entry, module: m.module, mapping: nil, orig: nil,
                                    onOpenStrong: openStrong, onOpenRef: onOpenRef, onOpenAll: { path.append(num) })
                        .id("\(m.module.id)|\(num)")
                }
            case .word(let m, let f)?:
                wordEntry(m, f)
            case nil:
                main(res)
            }
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Загрузка…").foregroundStyle(pal.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        }
    }

    @ViewBuilder private func main(_ res: LookupResult) -> some View {
        let mapping = res.mapping
        if mapping.mode == "approx" {
            WarnBox(icon: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("В переводе нет номеров Стронга. Примерные варианты по симфонии RST+:")
                    FlowRow {
                        ForEach(mapping.strongs, id: \.self) { s in
                            StrongChip(text: "\(s) · \(Int(((mapping.weights[s] ?? 0) * 100).rounded()))%")
                        }
                    }
                }
            }
        } else if mapping.mode != "exact" && res.results.isEmpty {
            WarnBox(icon: true) { Text("Не нашли это слово в оригинале.") }
        }
        let current = res.results.first { $0.module.id == selected }
        if let current {
            if res.results.count > 1 {
                UnderlineTabs(labels: res.results.map { $0.module.name },
                              index: res.results.firstIndex { $0.module.id == current.module.id } ?? 0) { i in
                    selected = res.results[i].module.id
                    entryIdx = 0
                }
            }
            if current.found.count > 1 {
                PillTabs(labels: current.found.map { f in f.key + ((f.entry["lemma"] as? String).map { " " + $0 } ?? "") },
                         index: min(entryIdx, current.found.count - 1)) { entryIdx = $0 }
            }
            let f = current.found[min(entryIdx, current.found.count - 1)]
            if current.module.dictionaryKind == "strongs" {
                StrongEntryView(num: f.key, entry: f.entry, module: current.module, mapping: mapping, orig: orig,
                                onOpenStrong: openStrong, onOpenRef: onOpenRef, onOpenAll: { path.append(f.key) })
                    .id("\(current.module.id)|\(f.key)")
            } else {
                wordEntry(current.module, f)
            }
        } else if res.results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "book.closed").font(.system(size: 34)).foregroundStyle(pal.muted)
                Text("Статей не найдено").font(.headline).foregroundStyle(pal.text)
                if res.dictionaryCount == 0 {
                    Text("Нет включённых словарей.").foregroundStyle(pal.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        } else {
            VStack(spacing: 8) {
                ForEach(res.results) { r in
                    DictRow(result: r) {
                        selected = r.module.id
                        entryIdx = 0
                    }
                }
            }
        }
    }

    // MARK: - Статья словаря «по словам»

    @ViewBuilder private func wordEntry(_ m: InstalledModule, _ f: Found) -> some View {
        let e = f.entry
        let refs = (e["refs"] as? [String]) ?? []
        Text((e["word"] as? String) ?? f.key)
            .font(.system(size: 22.4, weight: .bold))
            .foregroundStyle(pal.text)
        if f.match == "stem" {
            WarnBox(icon: false) { Text("Найдено по основе «\(req.text)» — возможно, это другое слово.") }
        } else if f.match == "root" {
            WarnBox(icon: false) { Text("Найдено по корню «\(req.text)».") }
        }
        if let o = e["original"] as? String, !o.isEmpty {
            Text(o).font(.system(size: 36.8)).foregroundStyle(pal.text)
        }
        let txt = (e["text"] as? String) ?? (e["definition"] as? String) ?? ""
        Text(EntryLinks.attributed(txt, accent: pal.accent))
            .lineSpacing(5)
            .foregroundStyle(pal.text)
            .environment(\.openURL, OpenURLAction { url in
                if let r = EntryLinks.verse(from: url) {
                    onOpenRef(r.0, r.1, r.2)
                } else if let w = StrongLinks.refWord(from: url) {
                    openSee(m, w)
                }
                return .handled
            })
        if !refs.isEmpty {
            FlowRow {
                ForEach(refs, id: \.self) { r in
                    if let p = OsisRef(r) {
                        RefChip(label: osisLabel(p), icon: "link") { onOpenRef(p.book, p.chapter, p.verse) }
                    }
                }
            }
        }
        SourceNote(lines: ["\(m.name) · \(m.license)"])
    }
}

/// «Быт. 1:1–3»
func osisLabel(_ p: OsisRef) -> String {
    var s = shortRef(p.book, p.chapter, p.verse)
    if let ec = p.endChapter, let ev = p.endVerse {
        s += ec == p.chapter ? "–\(ev)" : "–\(ec):\(ev)"
    }
    return s
}

// MARK: - Статья Стронга

struct StrongEntryView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.readerPalette) private var pal
    let num: String
    let entry: [String: Any]
    let module: InstalledModule
    let mapping: Mapping?
    let orig: OrigInfo?
    let onOpenStrong: (String) -> Void
    let onOpenRef: (String, Int, Int) -> Void
    let onOpenAll: () -> Void

    private var isHeb: Bool { num.hasPrefix("H") }

    private func str(_ k: String) -> String? {
        guard let s = entry[k] as? String, !s.isEmpty else { return nil }
        return s
    }

    var body: some View {
        // точная форма слова в этом стихе (номер совпадает с номером статьи)
        let exact: OrigInfo? = {
            guard let o = orig, let n = o.num else { return nil }
            return Align.strongNum(n) == Align.strongNum(num) ? o : nil
        }()
        let morph: [String] = exact != nil ? [] : (mapping?.mode == "exact" ? mapping!.morph : [])
        // как переведено в синодальном тексте — из симфонии RST+, если у самого словаря этого нет
        let sym: [String: Any]? = (module.id == Lexicon.symphonyId || entry["renderings"] != nil) ? nil
            : store.module(Lexicon.symphonyId).flatMap { store.dictEntry(module: $0, key: num) }
        let renderings = ((entry["renderings"] ?? sym?["renderings"]) as? [[Any]]).map { list in
            list.compactMap { p -> (String, Int)? in
                guard p.count >= 2, let w = p[0] as? String, let n = p[1] as? NSNumber else { return nil }
                return (w, n.intValue)
            }
        }
        let refs = entry["refs"] as? [String]
        let lex = module.id == Lexicon.symphonyId ? [] : Lexicon.lexiconEntries(store: store, num: num)

        VStack(alignment: .leading, spacing: 18) {
            headCard(exact: exact, morph: morph)
            if let d = str("definition") {
                section("Значение") { linked(d, size: 17) }
            }
            if let d = str("derivation") {
                section("Происхождение") { linked(d, size: 16) }
            }
            ForEach(Array(lex.enumerated()), id: \.offset) { _, x in
                LexSection(name: x.0.name, text: x.1)
            }
            if let r = renderings, !r.isEmpty {
                section("В Синодальном переводе") { RenderingsView(rows: r) }
            }
            if let t = str("text") {
                Text(t).lineSpacing(4).foregroundStyle(.primary).iosCard()
            }
            if let refs, !refs.isEmpty {
                section(renderings != nil ? "Где встречается" : "Связанные стихи") {
                    FlowRow {
                        ForEach(refs, id: \.self) { r in
                            if let p = OsisRef(r) {
                                RefChip(label: osisLabel(p)) { onOpenRef(p.book, p.chapter, p.verse) }
                            }
                        }
                    }
                }
            }
            WordStatsBlock(num: num, onOpenRef: onOpenRef, onOpenAll: onOpenAll)
            SourceNote(lines: {
                var l = ["\(module.name) · \(module.license)"]
                if sym != nil, renderings != nil, let s = store.module(Lexicon.symphonyId) { l.append("\(s.name) · \(s.license)") }
                for (m, _) in lex { l.append("\(m.name): \(m.author)" + (m.license.isEmpty ? "" : " · \(m.license)")) }
                return l
            }())
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SecTitle(text: title)
            c().iosCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Текст с нажимаемыми номерами Стронга («от H24 (אָבִיב)»)
    private func linked(_ s: String, size: CGFloat) -> some View {
        var a = StrongLinks.attributed(s)
        for run in a.runs where run.link != nil {
            a[run.range].foregroundColor = pal.accent
        }
        return Text(a)
            .font(.system(size: size))
            .lineSpacing(size * 0.25)
            .foregroundStyle(.primary)
            .environment(\.openURL, OpenURLAction { url in
                if let k = StrongLinks.key(from: url) { onOpenStrong(k) }
                return .handled
            })
    }

    private func headCard(exact: OrigInfo?, morph: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lemma = str("lemma") {
                Text(lemma)
                    .font(.system(size: 40, design: isHeb ? .serif : .default))
                    .foregroundStyle(pal.text)
                    .frame(maxWidth: .infinity, alignment: isHeb ? .trailing : .leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.bottom, 4)
            }
            metaLine
            if let exact {
                hereRow("В этом стихе", first: true) {
                    Text(exact.orig) + Text(exact.morph.flatMap { Morph.describe($0) }.map { " — " + $0 } ?? "")
                }
            }
            ForEach(Array(morph.enumerated()), id: \.offset) { i, m in
                hereRow("Грамматическая форма", first: i == 0) {
                    Text((Morph.describe(m) ?? NSLocalizedString("без расшифровки", comment: "")) + " ")
                        + Text("(\(m))").font(.system(size: 13.5, design: .monospaced)).foregroundColor(pal.muted)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var metaLine: some View {
        var parts: [Text] = []
        if let x = str("xlit") { parts.append(Text(x).italic().foregroundColor(pal.text)) }
        if let p = str("pron"), p != str("xlit") { parts.append(Text(p)) }
        parts.append(Text(num).font(.system(size: 13.6, design: .monospaced)).foregroundColor(pal.accent))
        parts.append(Text(isHeb ? "иврит / арамейский (ВЗ)" : "греческий (НЗ)"))
        var out = Text("")
        for (i, p) in parts.enumerated() {
            if i > 0 { out = out + Text("  ·  ").foregroundColor(pal.muted.opacity(0.6)) }
            out = out + p
        }
        return out.font(.system(size: 14.4)).foregroundStyle(pal.muted).lineSpacing(3)
    }

    private func hereRow(_ label: String, first: Bool, _ value: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if first {
                Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.bottom, 10)
            }
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            value().font(.system(size: 16)).foregroundStyle(.primary).lineSpacing(3)
        }
        .padding(.top, first ? 6 : 6)
    }
}

// MARK: - Части статьи

/// Подпись раздела: мелко, прописными, с разрядкой
struct SecTitle: View {
    @Environment(\.readerPalette) private var pal
    let text: String
    var extra: String? = nil

    var body: some View {
        (Text(text).font(.system(size: 17, weight: .semibold))
            + Text(extra.map { " · " + $0 } ?? "").font(.system(size: 17, weight: .regular)))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

/// Тёплая плашка-предупреждение
struct WarnBox<C: View>: View {
    @Environment(\.readerPalette) private var pal
    var icon = true
    @ViewBuilder let content: () -> C

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if icon {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(hex: 0xb7791f))
            }
            content().font(.system(size: 15)).foregroundStyle(pal.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xf6c343).opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Номер Стронга плашкой
struct StrongChip: View {
    @Environment(\.readerPalette) private var pal
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.7, design: .monospaced))
            .foregroundStyle(pal.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(pal.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Плашка-место («Быт. 2:20»)
struct RefChip: View {
    @Environment(\.readerPalette) private var pal
    let label: String
    var icon: String? = nil
    var count: Int? = nil
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 13)) }
                Text(label).font(.system(size: 16)).lineLimit(1)
                if let count { Text("\(count)").font(.system(size: 13)).foregroundStyle(on ? pal.accent : pal.muted) }
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(on ? pal.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Плашки с переносом по строкам
struct FlowRow<C: View>: View {
    @ViewBuilder let content: () -> C

    var body: some View {
        InterlinearFlow(hSpacing: 8, vSpacing: 8) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Источник: линия сверху и серый мелкий текст
struct SourceNote: View {
    @Environment(\.readerPalette) private var pal
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(pal.muted.opacity(0.2)).frame(height: 1)
            Text(lines.joined(separator: "\n")).font(.system(size: 13.5)).foregroundStyle(pal.muted).lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Вкладки словарей: подчёркнутые, листаются по горизонтали
struct UnderlineTabs: View {
    @Environment(\.readerPalette) private var pal
    let labels: [String]
    let index: Int
    let onTap: (Int) -> Void

    var body: some View {
        if labels.count <= 4 {
            Picker("", selection: Binding(get: { index }, set: { i in withAnimation(.easeInOut(duration: 0.24)) { onTap(i) } })) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in Text(l).tag(i) }
            }
            .pickerStyle(.segmented)
        } else {
            PillTabs(labels: labels, index: index, onTap: onTap)
        }
    }

    private var underlined: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                        Button { withAnimation(.easeInOut(duration: 0.24)) { onTap(i) } } label: {
                            VStack(spacing: 10) {
                                Text(l).font(.system(size: 17, weight: .medium)).lineLimit(1)
                                    .foregroundStyle(i == index ? pal.accent : pal.text.opacity(0.75))
                                Rectangle().fill(i == index ? pal.accent : Color.clear).frame(height: 3)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            Rectangle().fill(pal.muted.opacity(0.2)).frame(height: 1)
        }
        .padding(.horizontal, -16)
    }
}

/// Статьи одного словаря: таблетки
struct PillTabs: View {
    @Environment(\.readerPalette) private var pal
    let labels: [String]
    let index: Int
    let onTap: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                    Button { onTap(i) } label: {
                        Text(l).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            .foregroundStyle(i == index ? pal.accent : pal.text)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(i == index ? pal.accent.opacity(0.14) : pal.muted.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Строка списка словарей
struct DictRow: View {
    @Environment(\.readerPalette) private var pal
    let result: ModResult
    let onTap: () -> Void

    var body: some View {
        let r = result
        let kind = r.module.dictionaryKind == "strongs" ? "по номерам Стронга" : "по словам"
        let desc = r.found.map { $0.label.isEmpty ? $0.key : $0.label }.joined(separator: " · ")
            + (r.found.contains { $0.match == "stem" } ? " · по основе слова" : "")
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed").font(.system(size: 18)).foregroundStyle(pal.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.module.name).font(.system(size: 16, weight: .bold)).foregroundStyle(pal.text)
                    Text(desc).font(.system(size: 14.1)).foregroundStyle(pal.muted).lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(r.found.count > 1 ? "\(r.found.count) статьи" : kind)
                    .font(.system(size: 12.8)).foregroundStyle(pal.muted)
                    .multilineTextAlignment(.trailing).lineLimit(2)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Толковый словарь (Дворецкий): длинная статья — сначала 7 строк, по нажатию целиком
struct LexSection: View {
    @Environment(\.readerPalette) private var pal
    let name: String
    let text: String
    @State private var open = false

    var body: some View {
        let long = text.count > 420
        VStack(alignment: .leading, spacing: 6) {
            SecTitle(text: name)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).lineSpacing(4).lineLimit(long && !open ? 7 : nil).foregroundStyle(.primary)
                if long {
                    MoreLink(label: open ? "Свернуть" : "Развернуть") { open.toggle() }
                }
            }
            .iosCard()
        }
    }
}

struct MoreLink: View {
    @Environment(\.readerPalette) private var pal
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.accent).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// Полосы: слово (или книга) — доля — число
struct BarsView: View {
    @Environment(\.readerPalette) private var pal
    let rows: [(String, Int)]
    var books = false

    var body: some View {
        let mx = max(1, rows.map { $0.1 }.max() ?? 1)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                GeometryReader { g in
                    let labelW = books ? 56 : (g.size.width - 46 - 20) * 0.4
                    let barW = g.size.width - labelW - 46 - 20
                    let w = min(1, max(0.03, CGFloat(r.1) / CGFloat(mx)))
                    HStack(spacing: 10) {
                        Text(r.0).font(.system(size: books ? 14 : 16)).foregroundStyle(books ? Color.secondary : Color.primary)
                            .lineLimit(1).frame(width: labelW, alignment: .leading)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule().fill(pal.accent).frame(width: barW * w)
                        }
                        .frame(width: barW, height: 6)
                        Text("\(r.1)").font(.system(size: 14).monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: books ? 22 : 25)
            }
        }
    }
}

/// «В Синодальном переводе»: 6 самых частых, остальные — по «Ещё N»
struct RenderingsView: View {
    let rows: [(String, Int)]
    @State private var all = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BarsView(rows: all ? rows : Array(rows.prefix(6)))
            if !all && rows.count > 6 {
                MoreLink(label: "Ещё \(rows.count - 6)") { all = true }
            }
        }
    }
}

/// «Где встречается»: три плитки, полосы по книгам, первые места, «Все места (n)»
struct WordStatsBlock: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.readerPalette) private var pal
    let num: String
    let onOpenRef: (String, Int, Int) -> Void
    let onOpenAll: () -> Void
    @State private var st: WordStats?
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Считаю…").font(.system(size: 14)).foregroundStyle(pal.muted)
                }
                .padding(.vertical, 8)
            } else if let st, st.total > 0 {
                stats(st)
            }
        }
        .task(id: num) {
            loaded = false
            st = await StrongStats.load(store: store, num: num)
            loaded = true
        }
    }

    private func tile(_ n: Int, _ word: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundStyle(pal.text)
            Text(word).font(.system(size: 14)).foregroundStyle(pal.muted).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private func stats(_ st: WordStats) -> some View {
        let order = Dictionary(uniqueKeysWithValues: st.byBook.enumerated().map { ($1.0, $0) })
        let top = st.byBook.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : (order[a.0] ?? 0) < (order[b.0] ?? 0) }.prefix(6)
        let books = st.byBook.count
        VStack(alignment: .leading, spacing: 10) {
            SecTitle(text: "Где встречается", extra: st.module)
            HStack(spacing: 8) {
                tile(st.total, ruPlural(st.total, ["употребление", "употребления", "употреблений"]))
                tile(st.verses, ruPlural(st.verses, ["стих", "стиха", "стихов"]))
                tile(books, ruPlural(books, ["книга", "книги", "книг"]))
            }
            if books > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    BarsView(rows: top.map { ((Books.info($0.0)?.short ?? $0.0).replacingOccurrences(of: ".", with: ""), $0.1) }, books: true)
                    if books > top.count {
                        Text("И ещё в \(books - top.count) книгах.").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                .iosCard()
            }
            FlowRow {
                ForEach(st.refs.prefix(8)) { r in
                    RefChip(label: shortRef(r.book, r.chapter, r.verse)) { onOpenRef(r.book, r.chapter, r.verse) }
                }
            }
            Button(action: onOpenAll) {
                Text("Все места (\(st.verses))")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(pal.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Все места

struct ConcordanceView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.readerPalette) private var pal
    @Environment(\.dismiss) private var dismiss
    let num: String
    let lemma: String?
    let onOpenRef: (String, Int, Int) -> Void
    @State private var st: WordStats?
    @State private var loaded = false
    @State private var book: String?
    @State private var chapter: Int?
    @State private var word: String?
    @State private var shown = 40

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Все места · \(num)" + ((lemma?.isEmpty == false) ? " \(lemma!)" : ""),
                subtitle: (st.map { $0.total > 0 } ?? false)
                    ? "\(st!.total) \(ruPlural(st!.total, ["раз", "раза", "раз"])) в \(st!.verses) \(ruPlural(st!.verses, ["стихе", "стихах", "стихах"])) · \(st!.module)" : "",
                onBack: { dismiss() },
                onClose: nil
            )
            if !loaded {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ищу все места…").foregroundStyle(pal.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let st, st.total > 0 {
                list(st)
            } else {
                Text("В переводе со Стронгом этого слова нет.").foregroundStyle(pal.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            st = await StrongStats.load(store: store, num: num)
            loaded = true
        }
    }

    private func chipsRow<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { c() }.padding(.horizontal, 16)
        }
    }

    private struct Model {
        var all: [WordStats.Ref] = []
        var booksOrder: [String] = []
        var books: [String: Int] = [:]
        var chapters: [Int: Int] = [:]
        var inPlace: [WordStats.Ref] = []
        var filtered: [WordStats.Ref] = []
        var counts: [String: Int] = [:]
        var renderings: [String] = []
    }

    private func model(_ st: WordStats) -> Model {
        var m = Model()
        m.all = st.refs
        for r in m.all {
            if m.books[r.book] == nil { m.booksOrder.append(r.book) }
            m.books[r.book, default: 0] += 1
            if r.book == book { m.chapters[r.chapter, default: 0] += 1 }
        }
        m.inPlace = m.all.filter { (book == nil || $0.book == book) && (chapter == nil || $0.chapter == chapter) }
        m.filtered = m.inPlace.filter { word == nil || $0.words.contains(word!) }
        var order: [String] = []
        for r in m.inPlace {
            var seen = Set<String>()
            for w in r.words where seen.insert(w).inserted {
                if m.counts[w] == nil { order.append(w) }
                m.counts[w, default: 0] += 1
            }
        }
        let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        m.renderings = Array(order.sorted { a, b in
            (m.counts[a] ?? 0) != (m.counts[b] ?? 0) ? (m.counts[a] ?? 0) > (m.counts[b] ?? 0) : (pos[a] ?? 0) < (pos[b] ?? 0)
        }.prefix(14))
        return m
    }

    @ViewBuilder private func list(_ st: WordStats) -> some View {
        let md = model(st)
        let all = md.all
        let booksOrder = md.booksOrder
        let books = md.books
        let chapters = md.chapters
        let inPlace = md.inPlace
        let filtered = md.filtered
        let counts = md.counts
        let renderings = md.renderings
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if booksOrder.count > 1 {
                        chipsRow {
                            RefChip(label: "Все книги", count: all.count, on: book == nil) { book = nil; chapter = nil; word = nil; shown = 40 }
                            ForEach(booksOrder, id: \.self) { b in
                                RefChip(label: (Books.info(b)?.short ?? b).replacingOccurrences(of: ".", with: ""), count: books[b], on: book == b) {
                                    book = book == b ? nil : b
                                    chapter = nil; word = nil; shown = 40
                                }
                            }
                        }
                    }
                    if book != nil && chapters.count > 1 {
                        chipsRow {
                            RefChip(label: "Все главы", count: books[book!], on: chapter == nil) { chapter = nil; word = nil; shown = 40 }
                            ForEach(chapters.keys.sorted(), id: \.self) { c in
                                RefChip(label: "Гл. \(c)", count: chapters[c], on: chapter == c) {
                                    chapter = chapter == c ? nil : c
                                    word = nil; shown = 40
                                }
                            }
                        }
                    }
                    chipsRow {
                        RefChip(label: "Все", count: inPlace.count, on: word == nil) { word = nil; shown = 40 }
                        ForEach(renderings, id: \.self) { w in
                            RefChip(label: w, count: counts[w], on: word == w) { word = w; shown = 40 }
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
                VStack(spacing: 0) {
                    ForEach(Array(filtered.prefix(shown).enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16) }
                        Button { onOpenRef(r.book, r.chapter, r.verse) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shortRef(r.book, r.chapter, r.verse)).font(.system(size: 14, weight: .bold)).foregroundStyle(pal.accent)
                                Text(highlighted(r)).font(.system(size: 16)).lineSpacing(4).foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
                if filtered.count > shown {
                    Button { shown += 40 } label: {
                        Text("Показать ещё (\(filtered.count - shown))")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(pal.accent)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
            .padding(.bottom, 30)
        }
    }

    /// Текст стиха, слова с этим номером — на подложке
    private func highlighted(_ r: WordStats.Ref) -> AttributedString {
        let raw = store.verseRaw(module: st?.moduleId ?? "", book: r.book, chapter: r.chapter, verse: r.verse) ?? ""
        let target = Align.strongNum(num)
        var out = AttributedString()
        for t in Align.tokenize(raw) {
            var piece = AttributedString(t.text)
            if t.isWord && t.strongs.contains(where: { Align.strongNum($0) == target }) {
                piece.backgroundColor = pal.accent.opacity(0.22)
            }
            out += piece
        }
        return out
    }
}

// MARK: - Стиль iOS

extension View {
    /// Карточка группы iOS: белая (в тёмной теме — серая) плашка со скруглением
    func iosCard() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Шапка листа: слева «назад», по центру заголовок с подписью, справа «закрыть» — круглые стеклянные кнопки
struct SheetHeader: View {
    let title: String
    let subtitle: String
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) { Image(systemName: "chevron.left").chromeCircle() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Назад")
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            VStack(spacing: 1) {
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").chromeCircle() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Ссылки на стихи в тексте статьи

enum EntryLinks {
    private static let refRe = try! NSRegularExpression(pattern: "((?:[1-4]\\s?)?[А-ЯЁA-Z][а-яёa-z]{1,14}\\.?)\\s?(\\d{1,3})(?:\\s?[:,]\\s?(\\d{1,3})(?:\\s?[-–]\\s?(\\d{1,3}))?)?")

    /// Номера Стронга, «См. слово» и ссылки на стихи («Быт. 23:19») — нажимаемые
    static func attributed(_ s: String, accent: Color) -> AttributedString {
        var a = StrongLinks.attributed(s, refs: true)
        let ns = s as NSString
        for m in refRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            guard let book = RefParser.findBook(name), let ch = Int(ns.substring(with: m.range(at: 2))) else { continue }
            let hasVerse = m.range(at: 3).location != NSNotFound
            // целая глава — только у сокращений («Мф. 5», «Пс 22»)
            if !hasVerse && !(name.hasSuffix(".") || name.replacingOccurrences(of: " ", with: "").count <= 5) { continue }
            let v = hasVerse ? (Int(ns.substring(with: m.range(at: 3))) ?? 1) : 1
            guard let r = Range(m.range, in: s) else { continue }
            let lo = s.distance(from: s.startIndex, to: r.lowerBound)
            let hi = s.distance(from: s.startIndex, to: r.upperBound)
            let x = a.index(a.startIndex, offsetByCharacters: lo)
            let y = a.index(a.startIndex, offsetByCharacters: hi)
            a[x..<y].link = URL(string: "aobverseref:\(book).\(ch).\(v)")
        }
        for run in a.runs where run.link != nil {
            a[run.range].foregroundColor = accent
        }
        return a
    }

    static func verse(from url: URL) -> (String, Int, Int)? {
        guard url.scheme == "aobverseref" else { return nil }
        let p = String(url.absoluteString.dropFirst("aobverseref:".count)).split(separator: ".")
        guard p.count == 3, let c = Int(p[1]), let v = Int(p[2]) else { return nil }
        return (String(p[0]), c, v)
    }
}
