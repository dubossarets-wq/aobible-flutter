import PhotosUI
import SwiftUI

struct ImageRequest: Identifiable {
    let id = UUID()
    let text: String
    let ref: String
}

private struct ArtGradient: Identifiable {
    let id: String
    let title: String
    let colors: [Color]
    let paper: Bool
}

private let artGradients: [ArtGradient] = [
    ArtGradient(id: "g-stone", title: "Камень", colors: [Color(hex: 0x2B2A28), Color(hex: 0x4A4741), Color(hex: 0x6D675C)], paper: false),
    ArtGradient(id: "g-night", title: "Ночь", colors: [Color(hex: 0x0F1A2A), Color(hex: 0x1F3150), Color(hex: 0x2F4B7C)], paper: false),
    ArtGradient(id: "g-dawn", title: "Рассвет", colors: [Color(hex: 0xB4451F), Color(hex: 0xE88C6B), Color(hex: 0xF6C177)], paper: false),
    ArtGradient(id: "g-paper", title: "Бумага", colors: [Color(hex: 0xF3E9D7), Color(hex: 0xFAF3E6)], paper: true),
]

private enum ArtFormat: String, CaseIterable, Identifiable {
    case square, portrait, story
    var id: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .square: return 1
        case .portrait: return 1.25
        case .story: return 16.0 / 9.0
        }
    }

    var title: String {
        switch self {
        case .square: return "Квадрат"
        case .portrait: return "4:5"
        case .story: return "9:16"
        }
    }
}

/// Само изображение: фон (фото или градиент), текст стиха по центру (двигается и меняет размер), ссылка под ним
private struct ArtView: View {
    let text: String
    let ref: String
    let photo: UIImage?
    let gradient: ArtGradient
    let light: Bool
    let size: CGSize
    let scale: CGFloat
    let offset: CGSize

    private var baseFont: CGFloat {
        let len = max(40, Double(text.count))
        return size.width * CGFloat(min(0.085, max(0.04, 0.9 / len.squareRoot())))
    }

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                Color.black.opacity(0.28)
            } else {
                LinearGradient(colors: gradient.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(spacing: baseFont * 0.7) {
                Text("«\(text)»")
                    .font(.custom("PT Serif", size: baseFont * scale))
                    .multilineTextAlignment(.center)
                    .lineSpacing(baseFont * scale * 0.2)
                    .shadow(color: photo != nil ? .black.opacity(0.35) : .clear, radius: 8)
                Text(ref)
                    .font(.custom("PT Sans", size: baseFont * scale * 0.62).weight(.bold))
            }
            .foregroundStyle(light ? Color.white : Color(hex: 0x2A1A12))
            .padding(size.width * 0.09)
            .frame(width: size.width, height: size.height)
            .offset(offset)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// «Картинка со стихом»: фон (фото с сайта, своё фото или градиент), формат, размер текста; «Поделиться»
struct VerseImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    let ref: String

    @State private var photos: [[String: Any]] = []
    @State private var bg = "g-stone"
    @State private var photo: UIImage?
    @State private var format: ArtFormat = .square
    @State private var scale = 1.0
    @State private var offset = CGSize.zero
    @State private var dragBase = CGSize.zero
    @State private var pinchBase: Double?
    @State private var rendered: UIImage?
    @State private var item: PhotosPickerItem?

    private var gradient: ArtGradient {
        artGradients.first { $0.id == bg } ?? artGradients[0]
    }

    private var tone: String {
        (photos.first { ($0["id"] as? String) == bg }?["tone"] as? String) ?? "dark"
    }

    private var light: Bool {
        photo != nil ? tone != "light" : !gradient.paper
    }

    private let previewWidth: CGFloat = 330

    private var size: CGSize {
        CGSize(width: previewWidth, height: previewWidth * format.ratio)
    }

    private var key: String {
        "\(bg)|\(format.rawValue)|\(scale)|\(offset.width)|\(offset.height)|\(photo != nil)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ArtView(text: text, ref: ref, photo: photo, gradient: gradient, light: light, size: size, scale: scale, offset: offset)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .gesture(
                            DragGesture()
                                .onChanged { offset = CGSize(width: dragBase.width + $0.translation.width, height: dragBase.height + $0.translation.height) }
                                .onEnded { _ in dragBase = offset }
                        )
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged {
                                    if pinchBase == nil { pinchBase = scale }
                                    scale = min(2.5, max(0.5, (pinchBase ?? scale) * $0.magnification))
                                }
                                .onEnded { _ in pinchBase = nil }
                        )
                    Text("Двигайте текст пальцем, размер — двумя пальцами.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("Формат", selection: $format) {
                        ForEach(ArtFormat.allCases) { f in Text(LocalizedStringKey(f.title)).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Размер текста")
                        Slider(value: $scale, in: 0.5...2.5)
                        Button("как было") { scale = 1; offset = .zero; dragBase = .zero }
                            .font(.subheadline)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $item, matching: .images) {
                                VStack {
                                    Image(systemName: "photo.badge.plus").font(.title2)
                                    Text("Своё фото").font(.caption2)
                                }
                                .frame(width: 64, height: 64)
                                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            ForEach(artGradients) { g in
                                Button { pick(g.id) } label: {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(LinearGradient(colors: g.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 64, height: 64)
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(bg == g.id ? Color.accentColor : Color.clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(Array(photos.enumerated()), id: \.offset) { _, p in
                                if let id = p["id"] as? String, let thumb = p["thumb"] as? String {
                                    Button { pick(id) } label: {
                                        AsyncImage(url: URL(string: Net.bases[0] + "images/verse-bg/" + thumb)) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Color.gray.opacity(0.3)
                                        }
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(bg == id ? Color.accentColor : Color.clear, lineWidth: 3))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if let p = photos.first(where: { ($0["id"] as? String) == bg }) {
                        Text("Фото: \(p["title"] as? String ?? "")" + (p["author"].map { " — \($0)" } ?? "") + " (\(p["license"] as? String ?? ""))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Картинка со стихом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let img = rendered {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(ref, image: Image(uiImage: img))) {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .task {
                if let j = await Net.json("images/verse-bg/index.json"), let list = j["images"] as? [[String: Any]] {
                    photos = list
                    if let first = list.first?["id"] as? String { pick(first) }
                }
            }
            .task(id: key) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                render()
            }
            .onChange(of: item) { _, new in
                guard let new else { return }
                Task {
                    if let d = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        bg = "own"
                        photo = img
                    }
                }
            }
        }
    }

    private func pick(_ id: String) {
        bg = id
        guard let p = photos.first(where: { ($0["id"] as? String) == id }), let file = p["file"] as? String else {
            photo = nil
            return
        }
        photo = nil
        Task {
            if let d = try? await Net.fetch("images/verse-bg/" + file), let img = UIImage(data: d), bg == id {
                photo = img
            }
        }
    }

    /// Готовим файл 1080 пикселей в ширину — то, что уходит в «Поделиться»
    private func render() {
        let r = ImageRenderer(content: ArtView(text: text, ref: ref, photo: photo, gradient: gradient, light: light, size: size, scale: scale, offset: offset))
        r.scale = 1080 / previewWidth
        rendered = r.uiImage
    }
}
