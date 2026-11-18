import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension SermonStore {
    /// Копия проповеди: «Название — копия», у блоков новые номера; возвращает номер копии
    func duplicate(_ id: String) -> String? {
        guard var s = get(id) else { return nil }
        s.id = SermonStore.newId()
        s.title = String(localized: "\(s.title) — копия")
        s.blocks = s.blocks.map { b in
            var x = b
            x.id = SermonStore.newId()
            return x
        }
        let now = Date().timeIntervalSince1970 * 1000
        s.createdAt = now
        upsert(s)
        return s.id
    }

    /// Вставка блоков на нужное место (после блока с номером afterId; nil — в конец)
    func insert(_ blocks: [SermonBlock], into id: String, after afterId: String?) {
        guard var s = get(id) else { return }
        if let a = afterId, let i = s.blocks.firstIndex(where: { $0.id == a }) {
            s.blocks.insert(contentsOf: blocks, at: i + 1)
        } else {
            s.blocks.append(contentsOf: blocks)
        }
        upsert(s)
    }
}

/// «Печать и PDF»: аккуратная страница проповеди — серия, название, подзаголовок, дата; стихи с полосой слева и
/// подключёнными переводами; свой текст с **жирным** и *курсивом*; заметки для себя — мелко и приглушённо.
/// Файл PDF уходит в системное окно «Поделиться» (печать, сохранить, отправить)
enum SermonPDF {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let fmtRe = try! NSRegularExpression(pattern: "\\*\\*([^*\\n]+)\\*\\*|\\*([^*\\n]+)\\*")

    /// Свой текст: абзацы, **жирный**, *курсив*
    private static func rich(_ text: String) -> String {
        var out = ""
        for para in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n") {
            let ns = para as NSString
            var at = 0
            var line = ""
            for m in fmtRe.matches(in: para, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > at { line += esc(ns.substring(with: NSRange(location: at, length: m.range.location - at))) }
                if m.range(at: 1).location != NSNotFound {
                    line += "<b>" + esc(ns.substring(with: m.range(at: 1))) + "</b>"
                } else {
                    line += "<i>" + esc(ns.substring(with: m.range(at: 2))) + "</i>"
                }
                at = m.range.location + m.range.length
            }
            if at < ns.length { line += esc(ns.substring(from: at)) }
            out += "<p class=\"p\">" + (line.isEmpty ? "&nbsp;" : line) + "</p>"
        }
        return out
    }

    @MainActor
    static func html(_ s: Sermon) -> String {
        let ui = "'PT Sans',Helvetica,Arial,sans-serif"
        var h = """
        <html><head><meta charset="utf-8"><style>
        body{font-family:'PT Serif',Georgia,serif;font-size:12.5pt;line-height:1.4;color:#111;margin:0}
        .series{font:bold 9.5pt \(ui);letter-spacing:.6pt;color:#8a6b3f;margin:0 0 4pt}
        h1{font:bold 22pt \(ui);margin:0}
        .sub{font-size:13pt;color:#444;margin-top:4pt}
        .date{font:10pt \(ui);color:#777;margin-top:4pt}
        .v{border-left:3pt solid #8a6b3f;padding-left:12pt;margin:10pt 0}
        .ref{font:bold 10pt \(ui);color:#8a6b3f;margin:0 0 2pt}
        .n{font:bold 8pt \(ui);color:#8a6b3f}
        .altn{font:bold 8.5pt \(ui);color:#777;margin:5pt 0 0}
        .alt{font-size:11.5pt;color:#333;margin:0}
        .p{margin:5pt 0}
        .note{border-left:2pt solid #bbb;padding-left:10pt;margin:5pt 0;font-size:10.5pt;font-style:italic;color:#777}
        </style></head><body>
        """
        if let sr = s.series?.trimmingCharacters(in: .whitespaces), !sr.isEmpty { h += "<div class=\"series\">\(esc(sr.uppercased()))</div>" }
        h += "<h1>\(esc(s.title))</h1>"
        if let sub = s.subtitle?.trimmingCharacters(in: .whitespaces), !sub.isEmpty { h += "<div class=\"sub\">\(esc(sub))</div>" }
        if let d = SermonStore.dayText(s.date) { h += "<div class=\"date\">\(esc(d))</div>" }
        h += "<div style=\"height:14pt\"></div>"
        for b in s.blocks {
            if b.isVerse {
                let tx = SermonStore.verseTexts(b) ?? [b.text]
                h += "<div class=\"v\"><p class=\"ref\">\(esc(SermonStore.ref(b, full: true)))</p>"
                for (i, x) in tx.enumerated() {
                    if tx.count > 1, let v = b.verse {
                        h += "<p class=\"p\"><span class=\"n\">\(v + i) </span>\(esc(x))</p>"
                    } else {
                        h += "<p class=\"p\">\(esc(x))</p>"
                    }
                }
                for a in b.alt ?? [] {
                    let at = (a.t ?? []).map { a.il == true ? Markup.plain($0) : $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    if at.isEmpty { continue }
                    h += "<p class=\"altn\">\(esc(a.n ?? ""))</p><p class=\"alt\">\(esc(at))</p>"
                }
                h += "</div>"
            } else if !b.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                h += b.type == "note" ? "<div class=\"note\">\(rich(b.text))</div>" : rich(b.text)
            }
        }
        return h + "</body></html>"
    }

    /// PDF формата A4 с полями 46 / 50 pt
    @MainActor
    static func make(_ s: Sermon) -> Data {
        let fmt = UIMarkupTextPrintFormatter(markupText: html(s))
        let r = UIPrintPageRenderer()
        r.addPrintFormatter(fmt, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let area = CGRect(x: 46, y: 50, width: page.width - 92, height: page.height - 100)
        r.setValue(NSValue(cgRect: page), forKey: "paperRect")
        r.setValue(NSValue(cgRect: area), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<r.numberOfPages {
            UIGraphicsBeginPDFPage()
            r.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
}

/// Проповедь как файл PDF для «Поделиться»
struct SermonPDFFile: Transferable {
    let sermon: Sermon

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            let s = item.sermon
            let data = await MainActor.run { SermonPDF.make(s) }
            var name = s.title.components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|")).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if name.isEmpty { name = "sermon" }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".pdf")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
