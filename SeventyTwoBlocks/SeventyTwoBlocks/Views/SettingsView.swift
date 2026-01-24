import SwiftUI
import Auth

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var dayStartHour = 6
    @State private var streakThreshold = 36
    @State private var autoActivateSleepBlocks = true
    @State private var disableAutoContinue = false

    var body: some View {
        NavigationStack {
            Form {
                // Account section
                Section("Account") {
                    if let user = authManager.currentUser {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(user.email ?? "No email")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await authManager.signOut()
                            dismiss()
                        }
                    } label: {
                        Text("Sign Out")
                    }
                }

                // Day Settings
                Section("Day Settings") {
                    Picker("Day starts at", selection: $dayStartHour) {
                        ForEach(0..<9) { hour in
                            Text("\(hour):00").tag(hour)
                        }
                    }

                    Toggle("Auto-activate sleep blocks", isOn: $autoActivateSleepBlocks)
                }

                // Timer Settings
                Section("Timer") {
                    Toggle("Disable auto-continue", isOn: $disableAutoContinue)
                }

                // Goals
                Section("Goals") {
                    Stepper("Streak threshold: \(streakThreshold) blocks", value: $streakThreshold, in: 1...72)
                }

                // Categories
                Section("Categories") {
                    NavigationLink("Manage Categories") {
                        CategoriesSettingsView()
                    }
                }

                // Stats
                Section("Statistics") {
                    NavigationLink("Weekly Overview") {
                        Text("Weekly stats coming soon")
                    }
                    NavigationLink("Monthly Overview") {
                        Text("Monthly stats coming soon")
                    }
                    NavigationLink("Yearly Overview") {
                        Text("Yearly stats coming soon")
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CategoriesSettingsView: View {
    @EnvironmentObject var blockManager: BlockManager

    var body: some View {
        List {
            ForEach(blockManager.categories) { category in
                HStack {
                    Circle()
                        .fill(category.swiftUIColor)
                        .frame(width: 24, height: 24)

                    Text(category.label)

                    Spacer()

                    Text("\(category.labels.count) labels")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Categories")
        .task {
            await blockManager.loadCategories()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(BlockManager())
}
