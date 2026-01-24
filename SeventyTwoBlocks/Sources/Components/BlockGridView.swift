import SwiftUI

struct BlockGridView: View {
    let blocks: [Block]
    @Binding var selectedBlock: Block?

    // 8 columns for the grid
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(blocks) { block in
                BlockItemView(block: block)
                    .onTapGesture {
                        selectedBlock = block
                    }
            }
        }
    }
}

struct BlockItemView: View {
    let block: Block
    @EnvironmentObject var blockManager: BlockManager

    private var isCurrentBlock: Bool {
        block.blockIndex == Block.getCurrentBlockIndex()
    }

    private var isPastBlock: Bool {
        block.blockIndex < Block.getCurrentBlockIndex()
    }

    private var backgroundColor: Color {
        if block.isMuted {
            return Color(.systemGray5)
        }

        switch block.status {
        case .done:
            if let category = block.category,
               let cat = blockManager.categories.first(where: { $0.id == category }) {
                return cat.swiftUIColor.opacity(0.8)
            }
            return .green.opacity(0.8)
        case .skipped:
            return Color(.systemGray4)
        case .planned:
            if let category = block.category,
               let cat = blockManager.categories.first(where: { $0.id == category }) {
                return cat.swiftUIColor.opacity(0.3)
            }
            return .blue.opacity(0.3)
        case .idle:
            if isPastBlock {
                return Color(.systemGray5)
            }
            return Color(.systemBackground)
        }
    }

    private var borderColor: Color {
        if isCurrentBlock {
            return .primary
        }
        return Color(.systemGray4)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: isCurrentBlock ? 2 : 0.5)

            // Progress indicator
            if block.progress > 0 && block.status != .done {
                GeometryReader { geo in
                    Rectangle()
                        .fill(.primary.opacity(0.2))
                        .frame(width: geo.size.width * (block.progress / 100))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Block info
            VStack(spacing: 2) {
                if let label = block.label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }
            .padding(2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    BlockGridView(
        blocks: (0..<72).map { index in
            Block(
                id: UUID().uuidString,
                userId: "",
                date: "2024-01-01",
                blockIndex: index,
                isMuted: false,
                isActivated: false,
                category: nil,
                label: index % 5 == 0 ? "Task" : nil,
                note: nil,
                status: index < 10 ? .done : .idle,
                progress: 0,
                breakProgress: 0,
                runs: nil,
                activeRunSnapshot: nil,
                segments: [],
                usedSeconds: 0,
                createdAt: "",
                updatedAt: ""
            )
        },
        selectedBlock: .constant(nil)
    )
    .environmentObject(BlockManager())
    .padding()
}
