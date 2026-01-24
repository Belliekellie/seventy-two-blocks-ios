import SwiftUI

struct BlockSheetView: View {
    let block: Block
    @EnvironmentObject var blockManager: BlockManager
    @Environment(\.dismiss) private var dismiss

    @State private var category: String?
    @State private var label: String = ""
    @State private var status: BlockStatus = .idle

    private var blockTime: String {
        "\(Block.blockToTime(block.blockIndex)) - \(Block.blockEndTime(block.blockIndex))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Block info section
                Section {
                    HStack {
                        Text("Block \(Block.displayBlockNumber(block.blockIndex))")
                            .font(.headline)
                        Spacer()
                        Text(blockTime)
                            .foregroundStyle(.secondary)
                    }
                }

                // Timer section
                Section("Timer") {
                    HStack {
                        Image(systemName: "clock")
                        Text("20:00")
                            .font(.system(.title2, design: .monospaced))
                        Spacer()
                        Button("Start") {
                            // TODO: Implement timer
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Category section
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(blockManager.categories) { cat in
                                Button {
                                    category = category == cat.id ? nil : cat.id
                                } label: {
                                    Text(cat.label)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            category == cat.id
                                                ? cat.swiftUIColor.opacity(0.2)
                                                : Color(.systemGray6)
                                        )
                                        .foregroundStyle(
                                            category == cat.id
                                                ? cat.swiftUIColor
                                                : .primary
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(
                                                    category == cat.id
                                                        ? cat.swiftUIColor
                                                        : .clear,
                                                    lineWidth: 2
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Label section
                Section("Label") {
                    TextField("What are you doing?", text: $label)
                }

                // Status section
                Section("Mark as") {
                    HStack(spacing: 12) {
                        StatusButton(
                            title: "Done",
                            icon: "checkmark",
                            isSelected: status == .done,
                            color: .green
                        ) {
                            status = .done
                        }

                        StatusButton(
                            title: "Skipped",
                            icon: "xmark",
                            isSelected: status == .skipped,
                            color: .red
                        ) {
                            status = .skipped
                        }
                    }
                }

                // Time breakdown (for past blocks)
                if block.blockIndex < Block.getCurrentBlockIndex() {
                    Section("Time Breakdown") {
                        if block.segments.isEmpty && block.runs == nil {
                            Text("Available after block time passes")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            // TODO: Show breakdown
                            Text("20m total")
                        }
                    }
                }
            }
            .navigationTitle("Block Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            var updatedBlock = block
                            updatedBlock.category = category
                            updatedBlock.label = label.isEmpty ? nil : label
                            updatedBlock.status = status
                            await blockManager.saveBlock(updatedBlock)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                category = block.category
                label = block.label ?? ""
                status = block.status
            }
            .task {
                await blockManager.loadCategories()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct StatusButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.2) : Color(.systemGray6))
            .foregroundStyle(isSelected ? color : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BlockSheetView(block: Block(
        id: UUID().uuidString,
        userId: "",
        date: "2024-01-01",
        blockIndex: 30,
        isMuted: false,
        isActivated: false,
        category: nil,
        label: nil,
        note: nil,
        status: .idle,
        progress: 0,
        breakProgress: 0,
        runs: nil,
        activeRunSnapshot: nil,
        segments: [],
        usedSeconds: 0,
        createdAt: "",
        updatedAt: ""
    ))
    .environmentObject(BlockManager())
}
