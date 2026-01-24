//
//  ContentView.swift
//  SeventyTwoBlocks
//
//  Created by George Kelly on 24/01/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainView()
            } else {
                AuthView()
            }
        }
        .task {
            await authManager.checkSession()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(BlockManager())
}
