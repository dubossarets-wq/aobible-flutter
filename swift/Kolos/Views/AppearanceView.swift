import SwiftUI
import PhotosUI

/// Оформление: тема, шрифт, размер, интервалы, номера стихов, заголовки, сплошной текст, свой фон.
/// Образец закреплён сверху: любое изменение видно сразу
struct AppearanceView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("fontFamily") private var fontFamily = "system"
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("fontWeight") private var fontWeight = 400.0
    @AppStorage("lineHeight") private var lineHeight = 1.45
    @AppStorage("verseSpacing") private var verseSpacing = 0.55
    @AppStorage("showVerseNumbers") private var showNumbers = true
    @AppStorage("verseNumPos") private var verseNumPos = "sup"
    @AppStorage("showHeadings") private var showHeadings = true
    @AppStorage("headingColor") private var headingColor = HeadingStyle.defaultColor
    @AppStorage("headingSize") private var headingSize = HeadingStyle.defaultSize
    @AppStorage("continuousVerses") private var continuous = false
    @AppStorage("continuousComments") private var continuousComments = true
    @AppStorage("textMargin") private var textMargin = 14.0
    @AppStorage("hideOnScroll") private var hideOnScroll = true
    @AppStorage("readingStyle") private var readingStyle = "scroll"
    @AppStorage("bgImage") private var bgImage = 0
    @AppStorage("bgVeil") private var bgVeil = ReaderBackground.defaultVeil
    @AppStorage("bgBlur") private var bgBlur = 0.0
    @AppStorage("inlineCommentaries") private var inlineRaw = ""
    @AppStorage("commentView") private var commentView = "tag"
    @AppStorage("commentaryFontSize") private var commentaryFontSize = 19.0
    @EnvironmentObject private var store: ModuleStore

    @State private var photo: PhotosPickerItem?
    @State private var confirmReset = false
    @State private var bgError = false

    /// Выбранная тема, которой больше нет в списке (прежние «Мята», «Лаванда», «Закат»), считается светлой
    private var current: String {
        AppThemes.all.contains { $0.id == theme } ? theme : "light"
    }

    var body: some View {
        let pal = AppThemes.palette(current)
        Form {
            QuickSettingsLink()
            Section("Тема") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 14) {
                    ForEach(AppThemes.all) { t in
                        Button { theme = t.id } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(t.palette.bg)
                                    Circle().stroke(current == t.id ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: current == t.id ? 3 : 1)
                                    Text("Аа").font(.headline).foregroundStyle(t.palette.text)
                                    Circle().fill(t.palette.accent).frame(width: 12, height: 12).offset(x: 18, y: 18)
                                }
                                .frame(width: 56, height: 56)
                                Text(LocalizedStringKey(t.label)).font(.caption).foregroundStyle(.primary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Шрифт") {
                Picker("Шрифт", selection: $fontFamily) {
                    ForEach(ReadingFonts.all) { f in
                        Text(LocalizedStringKey(f.label)).tag(f.id)
                    }
                }
                .pinnable("fontFamily")
                row("Размер: \(Int(fontSize))", value: $fontSize, range: 13...40, step: 1, def: 19).pinnable("fontSize")
                row("Толщина: \(Int(fontWeight))", value: $fontWeight, range: 300...700, step: 100, def: 400).pinnable("fontWeight")
                row("Межстрочный интервал: \(String(format: "%.2f", lineHeight))", value: $lineHeight, range: 1.1...2.2, step: 0.05, def: 1.45).pinnable("lineHeight")
                row("Между стихами: \(String(format: "%.2f", verseSpacing))", value: $verseSpacing, range: 0...1.6, step: 0.05, def: 0.55).pinnable("verseSpacing")
                row("Поля по бокам: \(Int(textMargin))", value: $textMargin, range: 8...48, step: 2, def: 14).pinnable("textMargin")
            }
            Section("Текст") {
                // «Режим чтения» (прокрутка / страницы) — в «Ещё»
                Toggle("Номера стихов", isOn: $showNumbers).pinnable("showVerseNumbers")
                if showNumbers {
                    Picker("Номер стиха", selection: $verseNumPos) {
                        Text("Над строкой").tag("sup")
                        Text("В строке").tag("inline")
                    }
                    .pinnable("verseNumPos")
                }
                Toggle("Заголовки разделов", isOn: $showHeadings).pinnable("showHeadings")
                if showHeadings {
                    Picker("Цвет заголовков", selection: $headingColor) {
                        ForEach(HeadingStyle.colors, id: \.0) { c in Text(LocalizedStringKey(c.1)).tag(c.0) }
                    }
                    .pinnable("headingColor")
                    row("Размер заголовков: \(Int((headingSize * 100).rounded()))%", value: $headingSize, range: 0.7...1.3, step: 0.05, def: HeadingStyle.defaultSize).pinnable("headingSize")
                }
                Toggle("Сплошной текст (без разрывов между стихами)", isOn: $continuous).pinnable("continuousVerses")
                if continuous {
                    // в сплошном тексте толкования не встают под стихом — только значком после стиха
                    Toggle("Толкования значком после стиха", isOn: $continuousComments).pinnable("continuousComments")
                }
            }
            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(bgImage == 0 ? "Выбрать своё фото" : "Выбрать другое фото", systemImage: "photo.on.rectangle")
                }
                if bgImage != 0 {
                    row("Картинку видно: \(Int(100 - bgVeil))%", value: Binding(get: { 100 - bgVeil }, set: { bgVeil = 100 - $0 }), range: 5...70, step: 1, def: 100 - ReaderBackground.defaultVeil)
                    row("Размытие: \(blurWord)", value: $bgBlur, range: 0...20, step: 1, def: 0)
                    Button("Без фона", role: .destructive) {
                        ReaderBackground.remove()
                        bgImage = 0
                        bgVeil = ReaderBackground.defaultVeil
                        bgBlur = 0
                    }
                }
            } header: {
                Text("Фон под текстом")
            } footer: {
                if bgError { Text("Не удалось открыть эту картинку.").foregroundStyle(.red) }
            }
            if !store.commentaries.isEmpty {
                Section {
                    row("Размер текста: \(Int(commentaryFontSize)) px", value: $commentaryFontSize, range: 14...32, step: 1, def: 19).pinnable("commentaryFontSize")
                    CapsuleSwitcher(options: [("below", String(localized: "Под стихом")), ("tag", String(localized: "Меткой после стиха"))], selection: $commentView)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .pinnable("commentView")
                } header: {
                    Text("Комментарии в тексте")
                }
                Section {
                    ForEach(store.commentaries) { m in
                        Toggle(isOn: Binding(get: { inlineOn(m) }, set: { setInline(m, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                if m.title != m.name { Text(m.title).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } footer: {
                    Text("Отмеченные видны после стиха. Остальные — зажмите стих → «Комментарии».")
                }
            }
            Section {
                Button("Сбросить оформление", role: .destructive) { confirmReset = true }
                    // окно привязано к самой кнопке, а не к экрану: иначе всплывало у верхней карточки
                    .confirmationDialog("Вернуть оформление по умолчанию?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Сбросить", role: .destructive) { reset() }
                        Button("Отмена", role: .cancel) {}
                    }
            } footer: {
                Text("Любую настройку можно вынести в «Ещё»: проведите по ней пальцем вправо или зажмите.")
            }
        }
        // образец следует за экраном: меняете параметры внизу — видно вверху
        .safeAreaInset(edge: .top, spacing: 0) {
            sampleCard(pal)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
                // сплошная подложка: настройки уходят под образец, а не просвечивают между ним и заголовком экрана
                .background {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea(edges: .top)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 4)
                }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                bgError = false
                if let data = try? await item.loadTransferable(type: Data.self), let stamp = ReaderBackground.save(data) {
                    bgImage = stamp
                } else {
                    bgError = true
                }
                photo = nil
            }
        }
    }

    private var blurWord: String {
        let b = Int(bgBlur)
        if b == 0 { return String(localized: "нет") }
        if b < 7 { return String(localized: "лёгкое") }
        if b <= 13 { return String(localized: "среднее") }
        return String(localized: "сильное")
    }

    /// Какие комментарии видны в тексте: пусто — все установленные, иначе список номеров модулей (JSON)
    private func inlineIds() -> [String] {
        if inlineRaw.isEmpty { return store.commentaries.map { $0.id } }
        return (try? JSONDecoder().decode([String].self, from: Data(inlineRaw.utf8))) ?? []
    }

    private func inlineOn(_ m: InstalledModule) -> Bool { inlineIds().contains(m.id) }

    private func setInline(_ m: InstalledModule, _ on: Bool) {
        var ids = inlineIds()
        if on { if !ids.contains(m.id) { ids.append(m.id) } } else { ids.removeAll { $0 == m.id } }
        inlineRaw = (try? String(data: JSONEncoder().encode(ids), encoding: .utf8)) ?? ""
    }

    private func reset() {
        inlineRaw = ""; commentView = "tag"; commentaryFontSize = 19; continuousComments = true
        theme = "system"; fontFamily = "system"; fontSize = 19; fontWeight = 400; lineHeight = 1.45
        verseSpacing = 0.55; showNumbers = true; verseNumPos = "sup"; showHeadings = true; headingColor = HeadingStyle.defaultColor; headingSize = HeadingStyle.defaultSize; continuous = false; textMargin = 14; hideOnScroll = true; readingStyle = "scroll"
        ReaderBackground.remove()
        bgImage = 0; bgVeil = ReaderBackground.defaultVeil; bgBlur = 0
    }

    /// Ползунок с подписью и кнопкой «вернуть значение по умолчанию» (видна, когда значение сдвинуто)
    private func row(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, def: Double) -> some View {
        let changed = abs(value.wrappedValue - def) > step / 2
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button {
                    value.wrappedValue = def
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .opacity(changed ? 1 : 0)
                .disabled(!changed)
                .accessibilityLabel("Вернуть значение по умолчанию")
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private static let sampleVerses: [(Int, String)] = [
        (1, "Господь — Пастырь мой; я ни в чём не буду нуждаться:"),
        (2, "Он покоит меня на злачных пажитях и водит меня к водам тихим,"),
        (3, "подкрепляет душу мою, направляет меня на стези правды ради имени Своего."),
    ]

    /// Образец — как страница чтения: название книги, глава, заголовок раздела и стихи (тема, шрифт, интервалы, поля,
    /// номера, сплошной текст, фон). Высота — по тексту, не больше 210; что не вошло — плавно уходит вниз
    private func sampleCard(_ pal: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: fontSize * verseSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Псалтирь")
                    .font(ReadingFonts.font(fontFamily, size: fontSize * 0.75, weight: 600))
                    .foregroundStyle(pal.muted)
                Text("Псалом 22")
                    .font(ReadingFonts.font(fontFamily, size: fontSize * 1.35, weight: 800))
                    .foregroundStyle(pal.text)
            }
            if showHeadings {
                Text("Господь — Пастырь мой")
                    .font(ReadingFonts.font(fontFamily, size: fontSize * headingSize, weight: max(fontWeight, 600)))
                    .foregroundStyle(HeadingStyle.color(headingColor, pal))
            }
            if continuous {
                verseText(Self.sampleVerses, pal)
            } else {
                ForEach(Self.sampleVerses, id: \.0) { v in verseText([v], pal) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, textMargin)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxHeight: 210, alignment: .top)
        .clipped()
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 24)
            }
        }
        .background { ReaderBackdrop(pal: pal).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func verseText(_ verses: [(Int, String)], _ pal: ThemePalette) -> some View {
        Text(sampleText(verses, pal))
            .font(ReadingFonts.font(fontFamily, size: fontSize, weight: fontWeight))
            .lineSpacing(fontSize * (lineHeight - 1))
            .foregroundStyle(pal.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sampleText(_ verses: [(Int, String)], _ pal: ThemePalette) -> AttributedString {
        var s = AttributedString("")
        for (n, text) in verses {
            if showNumbers {
                var num = AttributedString("\(n) ")
                num.font = .system(size: fontSize * 0.62, weight: .semibold)
                if verseNumPos == "sup" { num.baselineOffset = fontSize * 0.32 }
                num.foregroundColor = pal.verseNum
                s += num
            }
            s += AttributedString(text + (continuous ? " " : ""))
        }
        return s
    }
}
