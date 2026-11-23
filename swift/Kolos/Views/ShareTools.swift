import SwiftUI
import UIKit

/// Системное меню «Поделиться» с произвольным набором (картинка, текст, ссылка)
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Кнопка «Поделиться» для картинки по ссылке: скачивает её (уже открытая берётся из кэша) и открывает системное
/// меню — уходит сама картинка и подпись (название, автор, лицензия, ссылка на источник). Нет сети — уходит одна подпись
struct ShareImageButton: View {
    let url: URL?
    let caption: String
    @State private var loading = false
    @State private var shown: ShareItems?

    var body: some View {
        Button {
            guard !loading else { return }
            loading = true
            Task {
                var items: [Any] = []
                if let url, let data = try? await URLSession.shared.data(from: url).0, let img = UIImage(data: data) {
                    items.append(img)
                }
                items.append(caption)
                loading = false
                shown = ShareItems(items: items)
            }
        } label: {
            if loading {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(url == nil && caption.isEmpty)
        .accessibilityLabel("Поделиться")
        .sheet(item: $shown) { s in
            ActivityView(items: s.items)
                .presentationDetents([.medium, .large])
        }
    }
}

extension BiblePlace {
    /// Ссылка на место в «Картах» Apple: у получателя открывается карта с отметкой
    var appleMapsURL: URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "ll", value: "\(lat),\(lng)"), URLQueryItem(name: "q", value: name)]
        return c?.url
    }

    var googleMapsURL: URL? {
        var c = URLComponents(string: "https://www.google.com/maps/search/")
        c?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(lat),\(lng)")]
        return c?.url
    }

    /// Текст для отправки: название, нынешнее название, координаты и ссылки на карты (открываются у любого получателя)
    var shareText: String {
        var lines = [name]
        if !modern.isEmpty { lines.append(modern) }
        lines.append(String(format: "%.5f, %.5f", lat, lng))
        if let u = appleMapsURL { lines.append("Apple Maps: \(u.absoluteString)") }
        if let u = googleMapsURL { lines.append("Google Maps: \(u.absoluteString)") }
        return lines.joined(separator: "\n")
    }
}
