import SwiftUI

/// Первый запуск: ставится основной перевод — значок, название, три этапа с отметками (как BootstrapScreen во Flutter).
/// Не удалось подключиться — сообщение и «Повторить». Закрывается сам, когда появился перевод
struct BootstrapView: View {
    @EnvironmentObject private var store: ModuleStore
    let onRetry: () -> Void
    @State private var appeared = false

    /// 0 — каталог, 1 — загрузка, 2 — установка
    private var stage: Int {
        let states = Set(store.busy.values)
        if states.contains("Подготовка…") { return 2 }
        if states.contains("Загрузка…") { return 1 }
        return 0
    }

    var body: some View {
        VStack(spacing: 22) {
            Image("Logo")
                .resizable()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 14, y: 10)
                .accessibilityLabel("Колос")
            if store.catalogError != nil {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                    Text("Не удалось подключиться к серверу. Проверьте интернет.")
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color(red: 0.71, green: 0.25, blue: 0.18))
                .padding(14)
                .background(Color(red: 0.71, green: 0.25, blue: 0.18).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    onRetry()
                } label: {
                    Label("Повторить", systemImage: "arrow.clockwise")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Готовлю Синодальный перевод, словари и параллельные места…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                VStack(alignment: .leading, spacing: 12) {
                    step(0, "Каталог модулей")
                    step(1, "Загрузка перевода")
                    step(2, "Установка")
                }
                Text("Это нужно только один раз — дальше Библия работает без интернета.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { appeared = true } }
    }

    private func step(_ i: Int, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if i < stage {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if i == stage {
                    ProgressView()
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 22, height: 22)
            Text(title).foregroundStyle(i <= stage ? Color.primary : Color.secondary)
        }
    }
}
