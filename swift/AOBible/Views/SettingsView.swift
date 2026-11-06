import SwiftUI

/// Настройки. Значения хранятся в системном хранилище приложения (@AppStorage) — как у всех приложений iOS
struct SettingsView: View {
    @AppStorage("showVerseNumbers") private var showVerseNumbers = true
    @AppStorage("showStrongs") private var showStrongs = false
    @AppStorage("syncScroll") private var syncScroll = true
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "ru"

    var body: some View {
        Form {
            Section {
                Picker("Язык", selection: $interfaceLanguage) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                    Text("Українська").tag("uk")
                }
            }
            Section("Чтение") {
                Toggle("Номера стихов", isOn: $showVerseNumbers)
                Toggle("Номера Стронга", isOn: $showStrongs)
                Toggle("Синхронная прокрутка панелей", isOn: $syncScroll)
            } footer: {
                Text("Номера Стронга показываются у слов, для которых в модуле есть подстрочник.")
            }
            Section {
                Toggle("Не гасить экран при чтении", isOn: $keepScreenOn)
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Оформление: тема и размер шрифта
struct AppearanceView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("lineHeight") private var lineHeight = 1.45

    var body: some View {
        Form {
            Section("Тема") {
                Picker("Тема", selection: $theme) {
                    Text("Как в системе").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Шрифт") {
                VStack(alignment: .leading) {
                    Text("Размер: \(Int(fontSize))")
                    Slider(value: $fontSize, in: 14...32, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Межстрочный интервал: \(lineHeight, specifier: "%.2f")")
                    Slider(value: $lineHeight, in: 1.2...2.0, step: 0.05)
                }
            }
            Section("Образец") {
                Text("Ты укажешь мне путь жизни: полнота радостей пред лицем Твоим, блаженство в деснице Твоей вовек.")
                    .font(.system(size: fontSize))
                    .lineSpacing(fontSize * (lineHeight - 1))
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("Сборка", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            }
            Section {
                Text("AO Bible — бесплатное некоммерческое приложение для чтения Библии.")
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
