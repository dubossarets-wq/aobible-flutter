import SwiftUI

@main
struct AOBibleApp: App {
    @StateObject private var store = ModuleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
