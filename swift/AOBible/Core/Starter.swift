import Foundation

/// Стартовые модули: на первом запуске ставится основной перевод, остальное (параллельные места, симфония, Стронг,
/// места, оригиналы, словарь на языке, Лопухин, карты, подстрочники) доустанавливается в фоне — читать можно сразу.
/// Список и правила — как у Flutter-версии (starter.dart)
@MainActor
enum Starter {
    private static let fullBible = [
        "cs": "kralicka", "de": "luther1912", "en": "bsb", "es": "rv1909", "fr": "segond1910", "hi": "hin-irv", "it": "riveduta",
        "ja": "bungo", "ko": "korrv", "pl": "gdanska", "pt": "biblia-livre", "sr": "dk-cyr", "sw": "swh-ulb", "zh": "cuv-s",
    ]
    private static let ntBible = ["hy": "arm-nt1853", "id": "alkitab-gratis", "ro": "ronbl", "uk": "ukr-kulish", "be": "be-nt1931"]
    private static let cyrillic: Set<String> = ["ru", "uk", "be", "bg", "sr"]
    private static let dictionary = ["ru": "nikifor", "uk": "nikifor", "be": "nikifor"]

    static func homeBible(_ lang: String) -> String {
        fullBible[lang] ?? (cyrillic.contains(lang) ? "rst-plus" : "bsb")
    }

    static func list(_ lang: String) -> [String] {
        var ids: [String] = [homeBible(lang), "rst-plus", "xrefs-rst", "rst-symphony", "strongs-ru-hebrew", "strongs-ru-greek", "bible-places", "bible-illustrations", "oshb", "byz-rp2018", dictionary[lang] ?? "easton"]
        if let nt = ntBible[lang] { ids.append(nt) }
        if !cyrillic.contains(lang) { ids.append(contentsOf: ["strongs-hebrew", "strongs-greek"]) }
        ids.append(contentsOf: ["bible-maps", "lopukhin", "vin-interlinear", "rst-interlinear", "dvoretsky-gr"])
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Ставит недостающие стартовые модули по одному. Модуль, который человек удалил, заново не ставится
    /// (он отмечен как «уже ставили»); не нашедшиеся в каталоге и недокачанные пробуем при следующем запуске
    static func run(store: ModuleStore, lang: String) async {
        if store.catalog.isEmpty { await store.loadCatalog() }
        guard !store.catalog.isEmpty else { return }
        let ud = UserDefaults.standard
        var done = Set(ud.stringArray(forKey: "starterDone") ?? [])
        let todo = list(lang).filter { store.module($0) == nil && !done.contains($0) }
        for (i, id) in todo.enumerated() {
            store.starterStatus = "Устанавливаю модули: \(i + 1) из \(todo.count)"
            guard let e = store.catalog.first(where: { $0.id == id }) else { continue }
            guard e.downloadable else { continue }
            await store.install(e)
            if store.module(id) != nil { done.insert(id) }
            ud.set(Array(done), forKey: "starterDone")
        }
        store.starterStatus = nil
    }
}
