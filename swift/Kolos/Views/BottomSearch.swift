import SwiftUI

/// Поле поиска внизу экрана в стекле: над клавиатурой, без неё — над нижним меню (как в «Словаре»).
/// Вместо системного поля поиска вверху (.searchable) — везде, где есть поиск
struct BottomSearchField<Trailing: View>: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var autofocus = false
    var submitLabel: SubmitLabel = .search
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: () -> Trailing
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить")
            }
            trailing()
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: 50)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            // клавиатура — после того, как экран встал на место
            if autofocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
        }
    }
}

extension BottomSearchField where Trailing == EmptyView {
    init(text: Binding<String>, prompt: LocalizedStringKey, autofocus: Bool = false,
         submitLabel: SubmitLabel = .search, onSubmit: @escaping () -> Void = {}) {
        self.init(text: text, prompt: prompt, autofocus: autofocus, submitLabel: submitLabel, onSubmit: onSubmit) { EmptyView() }
    }
}

extension View {
    /// Поиск внизу экрана (isOn — показывать ли поле сейчас)
    func bottomSearch(_ text: Binding<String>, prompt: LocalizedStringKey, isOn: Bool = true) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isOn { BottomSearchField(text: text, prompt: prompt) }
        }
    }
}
