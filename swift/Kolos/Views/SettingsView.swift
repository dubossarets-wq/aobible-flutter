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
    /// Тянут пункт нижнего меню — прокрутку страницы отключаем, чтобы пункт не «уплывал» вместе с ней
    @State private var tabDragging = false

    var body: some View {
        Form {
            TabBarSettings(dragging: $tabDragging)
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
                .pinnable("readingStyle")
                if readingStyle == "pages" {
                    Picker("Переносить стихи", selection: $pageVerseBreak) {
                        Text("Построчно").tag("line")
                        Text("По стихам").tag("verse")
                    }
                    .pinnable("pageVerseBreak")
                }
                // читать параллельно или нет: включить — рядом откроется второе окно с тем же переводом, выключить — останется одно
                ParallelToggle().pinnable("parallel")
                Toggle("Панели друг над другом", isOn: $panesStacked).pinnable("panesStacked")
                Toggle("Синхронная прокрутка", isOn: $syncScroll).pinnable("syncScroll")
                Toggle("Прятать меню при прокрутке", isOn: $hideOnScroll).pinnable("hideOnScroll")
                Toggle("Не гасить экран при чтении", isOn: $keepScreenOn).pinnable("keepScreenOn")
            } header: {
                Text("Чтение и листание")
            } footer: {
                if readingStyle == "pages" {
                    Text("В режиме «Страницы» доступно только одно окно.")
                    Text("«По стихам»: стих, который не помещается на странице, уходит на следующую целиком. «Построчно»: на следующую уходят только строки, что не поместились.")
                }
            }
            Section {
                Toggle("Номера стихов", isOn: $showVerseNumbers).pinnable("showVerseNumbers")
                Toggle("Номера Стронга", isOn: $showStrongs).pinnable("showStrongs")
                Toggle("Параллельные места после стиха", isOn: $showXrefs).pinnable("showXrefs")
                Toggle("Иллюстрации к стихам", isOn: $showIllustrations).pinnable("showIllustrations")
            } header: {
                Text("В тексте")
            } footer: {
                Text("Номера Стронга показываются у слов, для которых в модуле есть подстрочник.")
            }
            Section {} footer: {
                Text("Любую настройку можно вынести в «Ещё»: проведите по ней пальцем вправо или зажмите.")
            }
        }
        .scrollDisabled(tabDragging)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
    }
}
