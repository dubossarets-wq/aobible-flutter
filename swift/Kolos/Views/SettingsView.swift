import SwiftUI

/// Языки интерфейса: код, название на самом языке, флаг
let interfaceLanguages: [(String, String, String)] = [
    ("ru", "Русский", "🇷🇺"), ("uk", "Українська", "🇺🇦"), ("be", "Беларуская", "🇧🇾"), ("bg", "Български", "🇧🇬"),
    ("cs", "Čeština", "🇨🇿"), ("de", "Deutsch", "🇩🇪"), ("en", "English", "🇬🇧"), ("es", "Español", "🇪🇸"),
    ("fr", "Français", "🇫🇷"), ("hi", "हिन्दी", "🇮🇳"), ("hy", "Հայերեն", "🇦🇲"), ("id", "Bahasa Indonesia", "🇮🇩"),
    ("it", "Italiano", "🇮🇹"), ("ja", "日本語", "🇯🇵"), ("ka", "ქართული", "🇬🇪"), ("ko", "한국어", "🇰🇷"),
    ("pl", "Polski", "🇵🇱"), ("pt", "Português", "🇵🇹"), ("ro", "Română", "🇷🇴"), ("sr", "Српски", "🇷🇸"),
    ("sw", "Kiswahili", "🇹🇿"), ("zh", "中文", "🇨🇳"),
]

/// Настройки. Значения хранятся в системном хранилище приложения (@AppStorage) — как у всех приложений iOS
struct SettingsView: View {
    @AppStorage("showVerseNumbers") private var showVerseNumbers = true
    @AppStorage("showStrongs") private var showStrongs = false
    @AppStorage("syncScroll") private var syncScroll = true
    @AppStorage("readingStyle") private var readingStyle = "scroll"
    @AppStorage("pageVerseBreak") private var pageVerseBreak = "line"
    @AppStorage("hideOnScroll") private var hideOnScroll = true
    @AppStorage("showXrefs") private var showXrefs = true
    @AppStorage("showIllustrations") private var showIllustrations = true
    @AppStorage("panesStacked") private var panesStacked = true
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "ru"
    @EnvironmentObject private var panes: PanesStore

    var body: some View {
        Form {
            TabBarSettings()
            Section {
                Picker("Язык", selection: $interfaceLanguage) {
                    ForEach(interfaceLanguages, id: \.0) { l in
                        Text("\(l.2) \(l.1)").tag(l.0)
                    }
                }
            }
            // всё, что про чтение и листание, — в одном месте
            Section {
                Picker("Режим чтения", selection: $readingStyle) {
                    Text("Прокрутка").tag("scroll")
                    Text("Страницы").tag("pages")
                }
                // листать вместе можно не больше двух окон: лишние закрываются
                .onChange(of: readingStyle) { _, new in
                    if new == "pages" { panes.trimToLimit() }
                }
                if readingStyle == "pages" {
                    Picker("Переносить стихи", selection: $pageVerseBreak) {
                        Text("Построчно").tag("line")
                        Text("По стихам").tag("verse")
                    }
                }
                Toggle("Панели друг над другом", isOn: $panesStacked)
                Toggle("Синхронная прокрутка", isOn: $syncScroll)
                Toggle("Прятать меню при прокрутке", isOn: $hideOnScroll)
                Toggle("Не гасить экран при чтении", isOn: $keepScreenOn)
            } header: {
                Text("Чтение и листание")
            } footer: {
                if readingStyle == "pages" {
                    Text("В режиме «Страницы» открывается не больше двух окон.")
                    Text("«По стихам»: стих, который не помещается на странице, уходит на следующую целиком. «Построчно»: на следующую уходят только строки, что не поместились.")
                }
            }
            Section {
                Toggle("Номера стихов", isOn: $showVerseNumbers)
                Toggle("Номера Стронга", isOn: $showStrongs)
                Toggle("Параллельные места после стиха", isOn: $showXrefs)
                Toggle("Иллюстрации к стихам", isOn: $showIllustrations)
            } header: {
                Text("В тексте")
            } footer: {
                Text("Номера Стронга показываются у слов, для которых в модуле есть подстрочник.")
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
    }
}
