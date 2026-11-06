import SwiftUI

/// Оформление: тема, шрифт, размер, интервалы, номера стихов, заголовки, сплошной текст
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
    @AppStorage("continuousVerses") private var continuous = false
    @AppStorage("textMargin") private var textMargin = 14.0

    var body: some View {
        let pal = AppThemes.palette(theme)
        Form {
            Section("Тема") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 14) {
                    ForEach(AppThemes.all) { t in
                        Button { theme = t.id } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(t.palette.bg)
                                    Circle().stroke(theme == t.id ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: theme == t.id ? 3 : 1)
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
                row("Размер: \(Int(fontSize))", value: $fontSize, range: 13...40, step: 1)
                row("Толщина: \(Int(fontWeight))", value: $fontWeight, range: 300...700, step: 100)
                row("Межстрочный интервал: \(String(format: "%.2f", lineHeight))", value: $lineHeight, range: 1.1...2.2, step: 0.05)
                row("Между стихами: \(String(format: "%.2f", verseSpacing))", value: $verseSpacing, range: 0...1.6, step: 0.05)
                row("Поля по бокам: \(Int(textMargin))", value: $textMargin, range: 8...48, step: 2)
            }
            Section("Текст") {
                Toggle("Номера стихов", isOn: $showNumbers)
                if showNumbers {
                    Picker("Номер стиха", selection: $verseNumPos) {
                        Text("Над строкой").tag("sup")
                        Text("В строке").tag("inline")
                    }
                }
                Toggle("Заголовки разделов", isOn: $showHeadings)
                Toggle("Сплошной текст (без разрывов между стихами)", isOn: $continuous)
            }
            Section("Образец") {
                VStack(alignment: .leading, spacing: fontSize * verseSpacing) {
                    sample(1, "Господь — Пастырь мой; я ни в чём не буду нуждаться:")
                    sample(2, "Он покоит меня на злачных пажитях и водит меня к водам тихим,")
                }
                .padding(.vertical, 6)
                .listRowBackground(pal.bg)
            }
            Section {
                Button("Сбросить оформление", role: .destructive) {
                    theme = "system"; fontFamily = "system"; fontSize = 19; fontWeight = 400; lineHeight = 1.45
                    verseSpacing = 0.55; showNumbers = true; verseNumPos = "sup"; showHeadings = true; continuous = false; textMargin = 14
                }
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: range, step: step)
        }
    }

    private func sample(_ n: Int, _ text: String) -> some View {
        let pal = AppThemes.palette(theme)
        var s = AttributedString("")
        if showNumbers {
            var num = AttributedString("\(n) ")
            num.font = .system(size: fontSize * 0.62, weight: .semibold)
            if verseNumPos == "sup" { num.baselineOffset = fontSize * 0.32 }
            num.foregroundColor = pal.verseNum
            s += num
        }
        s += AttributedString(text)
        return Text(s)
            .font(ReadingFonts.font(fontFamily, size: fontSize, weight: fontWeight))
            .lineSpacing(fontSize * (lineHeight - 1))
            .foregroundStyle(pal.text)
    }
}
