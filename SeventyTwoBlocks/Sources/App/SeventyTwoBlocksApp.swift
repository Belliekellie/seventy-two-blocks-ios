import SwiftUI

@main
struct SeventyTwoBlocksApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var blockManager = BlockManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(blockManager)
        }
    }
}
