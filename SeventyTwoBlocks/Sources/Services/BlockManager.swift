import Foundation
import Supabase

@MainActor
final class BlockManager: ObservableObject {
    @Published var blocks: [Block] = []
    @Published var categories: [Category] = []
    @Published var isLoading = false
    @Published var error: String?

    private var currentDate: String = ""

    // MARK: - Load Blocks

    func loadBlocks(for date: Date) async {
        let dateString = formatDate(date)
        guard dateString != currentDate else { return }

        currentDate = dateString
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Fetch blocks for the date
            let fetchedBlocks: [Block] = try await supabase
                .from("blocks")
                .select()
                .eq("date", value: dateString)
                .order("block_index")
                .execute()
                .value

            // Create a full array of 72 blocks, filling in missing ones
            var fullBlocks: [Block] = []
            let blockDict = Dictionary(uniqueKeysWithValues: fetchedBlocks.map { ($0.blockIndex, $0) })

            for index in 0..<72 {
                if let existingBlock = blockDict[index] {
                    fullBlocks.append(existingBlock)
                } else {
                    // Create placeholder block
                    fullBlocks.append(createEmptyBlock(index: index, date: dateString))
                }
            }

            blocks = fullBlocks
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Update Block

    func updateBlock(_ block: Block, updates: [String: Any]) async {
        do {
            try await supabase
                .from("blocks")
                .update(updates)
                .eq("id", value: block.id)
                .execute()

            // Refresh blocks
            if let date = parseDate(block.date) {
                await loadBlocks(for: date)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Save Block

    func saveBlock(_ block: Block) async {
        do {
            try await supabase
                .from("blocks")
                .upsert(block)
                .execute()

            // Update local state
            if let index = blocks.firstIndex(where: { $0.id == block.id }) {
                blocks[index] = block
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Load Categories

    func loadCategories() async {
        do {
            let fetchedCategories: [Category] = try await supabase
                .from("categories")
                .select()
                .order("label")
                .execute()
                .value

            categories = fetchedCategories
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func createEmptyBlock(index: Int, date: String) -> Block {
        Block(
            id: UUID().uuidString,
            userId: "",
            date: date,
            blockIndex: index,
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
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
