import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

/// Цвета темы чтения: фон, текст, второстепенный текст, акцент, подсветка, номера стихов
struct ThemePalette {
    let bg: Color
    let text: Color
    let muted: Color
    let accent: Color
    let hl: Color
    let verseNum: Color
    let dark: Bool
}

struct ThemeDef: Identifiable {
    let id: String
    let label: String
    let palette: ThemePalette
    var id2: String { id }
}

/// Темы — те же цвета, что у Flutter-версии и веба. «Как в системе» — системные цвета iOS (светлая/тёмная сама)
enum AppThemes {
    static let system = ThemePalette(
        bg: Color(.systemBackground), text: Color.primary, muted: Color.secondary,
        accent: Color.accentColor, hl: Color.yellow.opacity(0.35), verseNum: Color.secondary, dark: false
    )

    private static func p(_ bg: UInt32, _ text: UInt32, _ muted: UInt32, _ accent: UInt32, _ hl: UInt32, _ num: UInt32, dark: Bool = false) -> ThemePalette {
        ThemePalette(bg: Color(hex: bg), text: Color(hex: text), muted: Color(hex: muted), accent: Color(hex: accent), hl: Color(hex: hl), verseNum: Color(hex: num), dark: dark)
    }

    static let all: [ThemeDef] = [
        ThemeDef(id: "system", label: "Как в системе", palette: system),
        ThemeDef(id: "light", label: "Светлая", palette: p(0xffffff, 0x121212, 0x5f5f5f, 0x1c1c1e, 0xfbe7a1, 0x6e6e6e)),
        ThemeDef(id: "warm", label: "Тёплая", palette: p(0xf6f5f2, 0x1d1c1a, 0x68655e, 0x8c5e28, 0xf6e3a8, 0x55524c)),
        ThemeDef(id: "sepia", label: "Сепия", palette: p(0xf3e9d7, 0x3b2f22, 0x6e604c, 0x8b5a24, 0xebd189, 0x6b5a44)),
        ThemeDef(id: "contrast", label: "Контраст", palette: p(0xffffff, 0x000000, 0x303030, 0x0037b3, 0xffe14d, 0x000000)),
        ThemeDef(id: "dark", label: "Тёмная", palette: p(0x161617, 0xdedbd4, 0x8d8a84, 0xd9a35c, 0x5b4a1c, 0xa7a39b, dark: true)),
        ThemeDef(id: "ocean", label: "Океан", palette: p(0x0f1a2a, 0xdfe7f1, 0x93a3b8, 0x5cb8f0, 0x1f4a6b, 0x8ea2bb, dark: true)),
        ThemeDef(id: "black", label: "Чёрная", palette: p(0x000000, 0xe4e4e4, 0x9a9a9a, 0xe8b86a, 0x4a3b12, 0x8f8f8f, dark: true)),
    ]

    /// Тема, которой больше нет в списке (прежние «Мята», «Лаванда», «Закат»), считается светлой
    static func palette(_ id: String) -> ThemePalette {
        if id == "system" { return system }
        return all.first { $0.id == id }?.palette ?? all.first { $0.id == "light" }?.palette ?? system
    }

    static func scheme(_ id: String) -> ColorScheme? {
        if id == "system" { return nil }
        return palette(id).dark ? .dark : .light
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = AppThemes.system
}

extension EnvironmentValues {
    var readerPalette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Шрифты чтения (файлы лежат в приложении; лицензии SIL OFL — те же, что у Flutter-версии)
struct FontDef: Identifiable {
    let id: String
    let label: String
}

enum ReadingFonts {
    static let all: [FontDef] = [
        FontDef(id: "system", label: "Системный"),
        FontDef(id: "PT Serif", label: "PT Serif"),
        FontDef(id: "Literata", label: "Literata"),
        FontDef(id: "Noto Serif", label: "Noto Serif"),
        FontDef(id: "Lora", label: "Lora"),
        FontDef(id: "PT Sans", label: "PT Sans"),
        FontDef(id: "IBM Plex Sans", label: "IBM Plex Sans"),
        FontDef(id: "Georgia", label: "Georgia"),
    ]

    static func weight(_ w: Double) -> Font.Weight {
        switch Int((max(100, min(900, w)) / 100).rounded()) {
        case 1: return .ultraLight
        case 2: return .thin
        case 3: return .light
        case 4: return .regular
        case 5: return .medium
        case 6: return .semibold
        case 7: return .bold
        case 8: return .heavy
        default: return .black
        }
    }

    static func uiWeight(_ w: Double) -> UIFont.Weight {
        switch Int((max(100, min(900, w)) / 100).rounded()) {
        case 1: return .ultraLight
        case 2: return .thin
        case 3: return .light
        case 4: return .regular
        case 5: return .medium
        case 6: return .semibold
        case 7: return .bold
        case 8: return .heavy
        default: return .black
        }
    }

    /// Тот же шрифт для UIKit (текст стихов рисуется своим слоем)
    static func uiFont(_ family: String, size: CGFloat, weight w: Double) -> UIFont {
        let wt = uiWeight(w)
        if family == "system" { return .systemFont(ofSize: size, weight: wt) }
        let d = UIFontDescriptor(fontAttributes: [.family: family]).addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: wt]])
        return UIFont(descriptor: d, size: size)
    }

    static func font(_ family: String, size: CGFloat, weight w: Double) -> Font {
        let wt = weight(w)
        if family == "system" { return .system(size: size, weight: wt) }
        return Font.custom(family, size: size).weight(wt)
    }
}
