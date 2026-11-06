import SwiftUI

@main
struct AOBibleApp: App {
    @StateObject private var store = ModuleStore()
    @StateObject private var marks = MarksStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(marks)
        }
    }
}
