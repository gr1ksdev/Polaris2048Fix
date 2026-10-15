import SwiftUI

@main
struct Polaris2048FixApp: App {
    @StateObject private var model = PolarisModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 610)
        }
        .windowResizability(.contentMinSize)
    }
}
