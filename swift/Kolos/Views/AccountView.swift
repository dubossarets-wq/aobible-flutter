import SwiftUI

/// Аккаунт Колоса: вход через Google, состояние синхронизации, выход и удаление аккаунта. Открывается из «Ещё» (самый верх)
struct AccountView: View {
    @ObservedObject private var account = AccountSync.shared
    @State private var accountError: String?
    @State private var confirmDelete = false

    private func errorText(_ e: String) -> String {
        switch e {
        case "not-configured": return String(localized: "Вход через Google скоро заработает.")
        case "offline": return String(localized: "Нет связи с интернетом — данные сойдутся, когда она появится.")
        case "auth": return String(localized: "Вход больше не действует — войдите снова.")
        case "quota": return String(localized: "В аккаунте закончилось место.")
        case "google": return String(localized: "Google не подтвердил вход. Попробуйте ещё раз.")
        default: return String(localized: "Не удалось: \(e)")
        }
    }

    /// Аккаунт: всё сохраняется в нём и появляется на других устройствах человека
    @ViewBuilder private var accountSection: some View {
        Section {
            if account.signedIn {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.state.email ?? account.state.name ?? "").font(.body.weight(.semibold))
                    if account.busy {
                        Text("Синхронизация…").font(.footnote).foregroundStyle(.secondary)
                    } else if let e = account.state.error {
                        Text(errorText(e)).font(.footnote).foregroundStyle(.red)
                    } else if let t = account.state.lastSync {
                        Text("Синхронизировано: \(day(t))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await account.sync() }
                } label: {
                    Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(account.busy)
                Button {
                    Task { await account.signOut() }
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(account.busy)
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Удалить аккаунт и данные на сервере", systemImage: "trash")
                }
            } else {
                if account.state.error == "auth" {
                    Text(errorText("auth")).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    accountError = nil
                    Task {
                        let e = await account.signIn()
                        accountError = e == nil || e == "canceled" ? nil : errorText(e!)
                    }
                } label: {
                    Label("Войти через Google", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(account.busy)
            }
            if let e = accountError {
                Text(e).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Аккаунт")
        } footer: {
            Text(account.signedIn
                 ? "Изменения сходятся при открытии приложения и когда вы из него выходите. При удалении аккаунта данные на этом телефоне останутся."
                 : "Войдите через Google — закладки, заметки, выделения, проповеди, планы и настройки сохранятся в аккаунте и появятся на других ваших устройствах (iPhone, Android, сайт).")
        }
        .confirmationDialog("Удалить аккаунт и все данные на сервере?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    let e = await account.deleteAccount()
                    accountError = e.map { errorText($0) }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func day(_ ms: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMMM, HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    var body: some View {
        Form { accountSection }
            .navigationTitle("Аккаунт")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Строка «Аккаунт» в самом верху «Ещё»: кто вошёл и когда сошлись данные (или приглашение войти)
struct AccountRow: View {
    @ObservedObject private var account = AccountSync.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.signedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.signedIn ? (account.state.email ?? account.state.name ?? String(localized: "Аккаунт")) : String(localized: "Войти в аккаунт"))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(account.signedIn
                     ? (account.busy ? String(localized: "Синхронизация…") : String(localized: "Закладки, заметки и настройки — на всех устройствах"))
                     : String(localized: "Сохраняйте закладки, заметки и настройки в аккаунте"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
