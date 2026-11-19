import SwiftUI
import CoreImage
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
        blurred = [:]
        return img
    }

    private static var blurred: [String: UIImage] = [:]
    private static let ci = CIContext()

    /// Картинка, размытая заранее, один раз: размытие на экране (.blur) пересчитывалось на каждом кадре прокрутки
    /// в каждом окне. radius — в пикселях самой картинки. Размытой картинке хватает малого размера: уменьшаем до 600
    static func blurredImage(_ stamp: Int, radius: CGFloat) -> UIImage? {
        guard let img = image(stamp) else { return nil }
        let r = (radius * 2).rounded() / 2
        guard r >= 0.5, let cg = img.cgImage else { return img }
        let key = "\(stamp)|\(r)"
        if let b = blurred[key] { return b }
        var src = CIImage(cgImage: cg)
        let k = min(1, 600 / max(src.extent.width, src.extent.height))
        if k < 1 { src = src.transformed(by: CGAffineTransform(scaleX: k, y: k)) }
        let ext = src.extent
        let out = src.clampedToExtent().applyingGaussianBlur(sigma: Double(r * k)).cropped(to: ext)
        guard let res = ci.createCGImage(out, from: ext) else { return img }
        let b = UIImage(cgImage: res)
        if blurred.count > 6 { blurred = [:] }
        blurred[key] = b
        return b
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
                    // радиус размытия на экране (в точках) → в пикселях картинки: во сколько раз она растянута
                    let s = max(g.size.width / max(1, img.size.width), g.size.height / max(1, img.size.height))
                    Image(uiImage: ReaderBackground.blurredImage(stamp, radius: blur / max(0.01, s)) ?? img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(1.04)
                        .clipped()
                }
                pal.bg.opacity(veil / 100)
            }
        }
        .ignoresSafeArea()
    }
}
