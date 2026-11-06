import SwiftUI

@main
struct AOBibleApp: App {
    @StateObject private var store = ModuleStore()
    @StateObject private var marks = MarksStore()
    @StateObject private var plans = PlansStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(marks)
                .environmentObject(plans)
        }
    }
}
