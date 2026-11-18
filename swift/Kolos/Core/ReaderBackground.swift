import SwiftUI
import ImageIO
import UIKit

/// Своя картинка под текстом Библии: файл в «Application Support», метка времени выбора — в настройке bgImage
/// (0 — фона нет, как у Flutter-версии). Вуаль цвета страницы поверх картинки (bgVeil, %, по умолчанию 72) и размытие (bgBlur, 0…20)
enum ReaderBackground {
    static let defaultVeil = 72.0

    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("reader-bg.jpg")
    }

    private static var cache: (stamp: Int, image: UIImage)?

    /// Сохранить выбранную картинку: уменьшаем до 1800 точек по длинной стороне. Возвращает метку времени или nil
    static func save(_ data: Data) -> Int? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try jpg.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        cache = nil
        return stamp
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
        cache = nil
    }

    static func image(_ stamp: Int) -> UIImage? {
        guard stamp != 0 else { return nil }
        if let c = cache, c.stamp == stamp { return c.image }
        guard let d = try? Data(contentsOf: url), let img = UIImage(data: d) else { return nil }
        cache = (stamp, img)
        return img
    }
}

/// Фон страницы чтения: цвет темы или своя картинка с вуалью и размытием
struct ReaderBackdrop: View {
    let pal: ThemePalette
    @AppStorage("bgImage") private var stamp = 0
    @AppStorage("bgVeil") private var veil = ReaderBackground.defaultVeil
    @AppStorage("bgBlur") private var blur = 0.0

    var body: some View {
        ZStack {
            pal.bg
            if let img = ReaderBackground.image(stamp) {
                GeometryReader { g in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(1.04)
                        .blur(radius: blur)
                        .clipped()
                }
                pal.bg.opacity(veil / 100)
            }
        }
        .ignoresSafeArea()
    }
}
