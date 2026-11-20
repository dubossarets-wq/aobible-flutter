import SwiftUI

/// Куда добавить стих: что сделать с выбранной проповедью (id)
struct SermonPick: Identifiable {
    let id = UUID()
    let onPick: (String) -> Void
}

/// «В проповедь»: список существующих проповедей (последние изменённые сверху), внизу — акцентная кнопка
/// «Новая проповедь» с плюсом
struct SermonPickerSheet: View {
    @EnvironmentObject private var sermons: SermonStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    /// Созданная проповедь: окно разворачивается и сразу открывает её
    @State private var newId: String?
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        let list = sermons.sermons.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        NavigationStack {
            List {
                if list.isEmpty {
                    Text("Проповедей пока нет — создайте новую.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(list) { s in
                            Button {
                                onPick(s.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title.isEmpty ? "Без названия" : s.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let sub = subtitle(s) {
                                        Text(sub).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Существующие")
                    }
                }
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                Button {
                    let id = sermons.create("Новая проповедь").id
                    onPick(id)
                    withAnimation { detent = .large }
                    newId = id
                } label: {
                    Label("Новая проповедь", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationDestination(item: $newId) { id in
                SermonEditor(id: id)
                    .navigationBarBackButtonHidden()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Закрыть")
                        }
                    }
            }
            .navigationTitle("В проповедь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        // Непрозрачный фон — внутри окна, а не presentationBackground: со своим presentationBackground система в iOS 26 не растягивает окно плавно из «парящего» вида на всю ширину (поднимается, а ширина прибавляется рывком)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    /// «Подзаголовок · дата»
    private func subtitle(_ s: Sermon) -> String? {
        let parts = [s.subtitle, s.date].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
