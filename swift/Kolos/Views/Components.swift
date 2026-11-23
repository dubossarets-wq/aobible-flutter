import SwiftUI

/// Строка списка со значком в цветном квадрате — как в «Настройках» iPhone
struct IconLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Пустая страница-заглушка: раздел ещё не перенесён на Swift
struct SoonView: View {
    let title: String
    let symbol: String

    var body: some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(title), systemImage: symbol)
        } description: {
            Text("Этот раздел скоро появится в новой версии.")
        }
    }
}

/// Переключатель в одну строку на всю ширину: плашки-капсулы поровну, выбранная — цветом акцента.
/// Вместо системного сегментного переключателя (окно «Подстрочник», выбор области поиска)
struct CapsuleSwitcher<T: Hashable>: View {
    let options: [(value: T, title: Text)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    o.title
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
