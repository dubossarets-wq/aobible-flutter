import SwiftUI

/// Настройки. Значения хранятся в системном хранилище приложения (@AppStorage) — как у всех приложений iOS
struct SettingsView: View {
    @AppStorage("showVerseNumbers") private var showVerseNumbers = true
    @AppStorage("showStrongs") private var showStrongs = false
    @AppStorage("syncScroll") private var syncScroll = true
    @AppStorage("showXrefs") private var showXrefs = true
    @AppStorage("panesStacked") private var panesStacked = true
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
            Section {
                Toggle("Номера стихов", isOn: $showVerseNumbers)
                Toggle("Номера Стронга", isOn: $showStrongs)
                Toggle("Параллельные места после стиха", isOn: $showXrefs)
                Toggle("Панели друг над другом", isOn: $panesStacked)
                Toggle("Синхронная прокрутка панелей", isOn: $syncScroll)
            } header: {
                Text("Чтение")
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
