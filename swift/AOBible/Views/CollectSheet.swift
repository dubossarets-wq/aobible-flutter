import SwiftUI

/// «В подборку»: добавить выделенные стихи в существующую подборку или создать новую
struct CollectSheet: View {
    @EnvironmentObject private var marks: MarksStore
    @Environment(\.dismiss) private var dismiss
    let items: [MarkItem]
    let done: (String) -> Void
    @State private var name = ""

    private func add(_ id: String?, _ name: String?) {
        if let n = marks.addToCollection(id: id, name: name, items: items) {
            done(n)
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Новая подборка: «К уроку», «Утешение»…", text: $name)
                            .submitLabel(.done)
                            .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { add(nil, name) } }
                        Button {
                            add(nil, name)
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Создать подборку")
                    }
                }
                if !marks.data.collections.isEmpty {
                    Section {
                        ForEach(marks.data.collections) { c in
                            Button {
                                add(c.id, nil)
                            } label: {
                                HStack {
                                    Label(c.name, systemImage: "folder").foregroundStyle(.primary)
                                    Spacer()
                                    if items.allSatisfy({ i in c.items.contains { $0.id == i.id } }) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    } else {
                                        Text("\(c.items.count) ст.").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("В подборку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
