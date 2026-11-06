import SwiftUI
import UIKit

let supportEmail = "dubossarets@gmail.com"
let telegramURL = "https://t.me/bystreetsky"

/// «Мои данные»: сохранить всё в файл, восстановить из файла, вернуть данные из резервной копии
struct MyDataView: View {
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var plans: PlansStore
    @EnvironmentObject private var sermons: SermonStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document = DataDocument(data: Data())
    @State private var pending: (entries: [String: String], at: Date?)?
    @State private var error: String?
    @State private var done: String?
    @State private var backups = UserData.backups()

    private func day(_ ms: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru")
        f.dateFormat = "d MMMM yyyy, HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    var body: some View {
        Form {
            Section {
                Text("Закладки, заметки, любимые стихи, выделения, планы, проповеди и настройки — в одном файле. Чтобы ничего не потерять при смене телефона. Файл открывается и в веб-версии, и в версии для Android.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    document = DataDocument(data: UserData.exportFile(UserData.collect(marks: marks, plans: plans, sermons: sermons)))
                    exporting = true
                } label: {
                    Label("Сохранить в файл", systemImage: "square.and.arrow.down")
                }
                Button { importing = true } label: {
                    Label("Восстановить из файла", systemImage: "square.and.arrow.up")
                }
            }
            if let e = error {
                Section { Text(e).foregroundStyle(.red) }
            }
            if let d = done {
                Section { Text(d).foregroundStyle(.green) }
            }
            if let p = pending {
                Section {
                    let c = UserData.counts(p.entries).map { "\($0.0) \($0.1)" }.joined(separator: ", ")
                    Text((p.at.map { "В файле от \(day($0.timeIntervalSince1970 * 1000)): " } ?? "В файле: ") + c)
                    Text("Всё на телефоне заменится данными из файла. Нынешнее останется в резервной копии.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Восстановить") {
                        UserData.snapshot("перед восстановлением из файла", marks: marks, plans: plans, sermons: sermons)
                        UserData.apply(p.entries, marks: marks, plans: plans, sermons: sermons)
                        pending = nil
                        backups = UserData.backups()
                        done = "Данные восстановлены."
                    }
                    Button("Отмена", role: .cancel) { pending = nil }
                }
            }
            Section {
                if backups.isEmpty {
                    Text("Копий пока нет — первая появится при следующем обновлении или восстановлении.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(backups) { b in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day(b.at))
                        Text(b.reason).font(.caption).foregroundStyle(.secondary)
                        Text(UserData.counts(b.entries).prefix(3).map { "\($0.0) \($0.1)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Вернуть эти данные") {
                            UserData.snapshot("перед возвратом из копии", marks: marks, plans: plans, sermons: sermons)
                            UserData.apply(b.entries, marks: marks, plans: plans, sermons: sermons)
                            backups = UserData.backups()
                            done = "Данные возвращены из копии."
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Резервные копии")
            } footer: {
                Text("Настройки, закладки, заметки и любимые стихи сохраняются перед каждым обновлением и восстановлением (последние 5 копий).")
            }
        }
        .navigationTitle("Мои данные")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "AO Bible — мои данные") { result in
            if case .success = result { done = "Файл сохранён." }
            if case .failure(let e) = result { error = e.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            error = nil
            done = nil
            switch result {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do {
                    pending = try UserData.parse(try Data(contentsOf: url))
                } catch {
                    self.error = "Это не файл с данными AO Bible."
                }
            case .failure(let e):
                error = e.localizedDescription
            }
        }
    }
}

/// «О приложении»: что это, версия, контакты, авторы и лицензии установленных модулей, программы и шрифты
struct AboutView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.openURL) private var openURL

    private let third: [(String, String, String)] = [
        ("SQLite", "SQLite Consortium", "Public Domain"),
        ("PT Sans, PT Serif", "ParaType", "SIL OFL 1.1"),
        ("Literata", "TypeTogether", "SIL OFL 1.1"),
        ("Lora", "Cyreal", "SIL OFL 1.1"),
        ("Noto Serif, Noto Serif Hebrew", "Google", "SIL OFL 1.1"),
        ("IBM Plex Sans", "IBM", "SIL OFL 1.1"),
    ]

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                Text("AO Bible — бесплатное некоммерческое приложение для чтения Библии: переводы, словари, толкования, планы чтения, аудио и проповеди. Работает без интернета, без рекламы и без отслеживания.")
                LabeledContent("Версия", value: version)
            }
            Section("Контакты") {
                Button {
                    if let u = URL(string: "mailto:\(supportEmail)") { openURL(u) }
                } label: { Label(supportEmail, systemImage: "envelope") }
                Button {
                    if let u = URL(string: telegramURL) { openURL(u) }
                } label: { Label("Telegram", systemImage: "paperplane") }
            }
            Section {
                Text("Данные закладок, заметок, планов и проповедей хранятся только на вашем телефоне. Приложение ничего не отправляет автоматически: письмо о проблеме вы видите и отправляете сами.")
                    .font(.footnote)
            } header: {
                Text("Конфиденциальность")
            }
            Section {
                ForEach(store.installed) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(m.name) — \(m.title)").font(.subheadline.weight(.semibold))
                        if !m.author.isEmpty { Text(m.author).font(.caption).foregroundStyle(.secondary) }
                        if !m.license.isEmpty { Text(m.license).font(.caption).foregroundStyle(.secondary) }
                        if let u = URL(string: m.source), m.source.hasPrefix("http") {
                            Button { openURL(u) } label: { Text(m.source).font(.caption).lineLimit(1) }
                        }
                    }
                }
            } header: {
                Text("Модули и их лицензии")
            } footer: {
                Text("Лицензии CC BY, BY-SA и BY-NC требуют указывать авторов — здесь они все в одном месте.")
            }
            Section("Программы и шрифты") {
                ForEach(third, id: \.0) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.0)
                        Text("\(t.1) · \(t.2)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// «Что нового»: записи по датам выпусков, новая — сверху
struct NewsView: View {
    @AppStorage("newsSeen") private var seen = ""

    private func title(_ id: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: PlanLogic.day0(id))
    }

    var body: some View {
        List {
            ForEach(newsEntries, id: \.id) { e in
                Section {
                    ForEach(e.items, id: \.self) { it in
                        Text(it)
                    }
                } header: {
                    Text(title(e.id))
                }
            }
        }
        .navigationTitle("Что нового")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seen = newsEntries.first?.id ?? "" }
    }
}

/// «Инструкция»: уроки по группам, шаги — текстом
struct HelpView: View {
    @State private var query = ""

    private var groups: [String] {
        var out: [String] = []
        for t in helpTours where !out.contains(t.group) { out.append(t.group) }
        return out
    }

    private func match(_ t: HelpTour) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || t.title.lowercased().contains(q) || t.steps.contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.self) { g in
                let items = helpTours.filter { $0.group == g && match($0) }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { t in
                            NavigationLink {
                                HelpLesson(tour: t)
                            } label: {
                                Label(t.title, systemImage: t.symbol)
                            }
                        }
                    } header: {
                        Text(g)
                    }
                }
            }
        }
        .navigationTitle("Инструкция")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Найти урок")
    }
}

struct HelpLesson: View {
    let tour: HelpTour

    var body: some View {
        List {
            ForEach(tour.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor, in: Circle())
                    Text(tour.steps[i])
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle(tour.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// «Сообщить о проблеме»: письмо разработчику с версией и устройством — текст виден до отправки
struct ReportView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.openURL) private var openURL
    @State private var text = ""

    private var info: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let d = UIDevice.current
        let s = UIScreen.main.bounds.size
        let mods = store.installed.map { $0.id }
        return [
            "AO Bible \(v) (\(b), Swift)",
            "\(d.systemName) \(d.systemVersion), \(d.model)",
            "\(Int(s.width))×\(Int(s.height))",
            "modules: \(mods.count) — \(mods.prefix(40).joined(separator: ", "))",
        ].joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text).frame(minHeight: 140)
            } header: {
                Text("Что случилось?")
            } footer: {
                Text("Откроется письмо с вашим описанием, версией приложения и устройством — вы сами видите текст перед отправкой. Ничего не отправляется автоматически.")
            }
            Section {
                Button("Написать письмо") {
                    var body = text + "\n\n\n— — —\n" + info
                    if body.count > 1800 { body = String(body.prefix(1800)) }
                    let q = "subject=" + "AO Bible: сообщение о проблеме".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
                        + "&body=" + body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
                    if let u = URL(string: "mailto:\(supportEmail)?\(q)") { openURL(u) }
                }
            }
        }
        .navigationTitle("Сообщить о проблеме")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Приветствие при первом запуске
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
                .padding(.top, 30)
            Text("Добро пожаловать в AO Bible")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                row("hand.tap", "Нажмите на слово — откроется его значение.")
                row("highlighter", "Зажмите стих на полсекунды — появятся действия: заметка, закладка, цвет, перевод рядом.")
                row("magnifyingglass", "Поиск — по слову, ссылке (Ин 3:16) или номеру Стронга.")
                row("calendar", "Планы чтения, аудио и проповеди — в нижнем меню и в «Ещё».")
            }
            Text("Приложение бесплатное, без рекламы и работает без интернета. Нужные переводы и словари скачиваются в «Ещё» → «Библиотека модулей»; самое важное поставится само.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: {
                Text("Начать").frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(24)
        .presentationDetents([.large])
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 30)
            Text(text)
        }
    }
}
