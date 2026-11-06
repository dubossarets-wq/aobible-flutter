import SwiftUI

@main
struct AOBibleApp: App {
    @StateObject private var store = ModuleStore()
    @StateObject private var marks = MarksStore()
    @StateObject private var plans = PlansStore()
    @StateObject private var panes = PanesStore()
    @StateObject private var sermons = SermonStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(marks)
                .environmentObject(plans)
                .environmentObject(panes)
                .environmentObject(sermons)
        }
    }
}
