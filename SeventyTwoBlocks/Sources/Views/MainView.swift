import SwiftUI

struct MainView: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var selectedDate = Date()
    @State private var selectedBlock: Block?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Date header
                    DateHeaderView(selectedDate: $selectedDate)

                    // Block grid - 72 blocks for the day
                    BlockGridView(
                        blocks: blockManager.blocks,
                        selectedBlock: $selectedBlock
                    )
                }
                .padding()
            }
            .navigationTitle("72 Blocks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $selectedBlock) { block in
                BlockSheetView(block: block)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .task {
            await blockManager.loadBlocks(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            Task {
                await blockManager.loadBlocks(for: newDate)
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
        .environmentObject(BlockManager())
}
