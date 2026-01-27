//
//  SeventyTwoBlocksApp.swift
//  SeventyTwoBlocks
//
//  Created by George Kelly on 24/01/2026.
//

import SwiftUI

@main
struct SeventyTwoBlocksApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var blockManager = BlockManager()
    @StateObject private var timerManager = TimerManager()
    @StateObject private var goalManager = GoalManager()
    @AppStorage("appearanceMode") private var appearanceMode: Int = 2  // 1 = light, 2 = dark

    private var colorScheme: ColorScheme {
        appearanceMode == 1 ? .light : .dark
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(blockManager)
                .environmentObject(timerManager)
                .environmentObject(goalManager)
                .preferredColorScheme(colorScheme)
        }
    }
}
