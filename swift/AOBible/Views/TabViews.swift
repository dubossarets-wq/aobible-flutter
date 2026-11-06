import SwiftUI

/// Планы чтения — пока заглушка
struct PlansView: View {
    var body: some View {
        NavigationStack {
            SoonView(title: "Планы чтения", symbol: "calendar")
                .navigationTitle("Планы чтения")
        }
    }
}
