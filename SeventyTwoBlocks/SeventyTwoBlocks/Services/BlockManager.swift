import Foundation
import Combine
import PostgREST
import Auth

@MainActor
final class BlockManager: ObservableObject {
    @Published var blocks: [Block] = []
    @Published var categories: [Category] = []
    @Published var favoriteLabels: [String] = []
    @Published var isLoading = false
    @Published var error: String?

    private var currentDate: String = ""
    private var categoriesLoaded = false
    private var categoriesAreDefaults = false  // Track if we fell back to defaults
    private var favoriteLabelsLoaded = false

    // MARK: - Load Blocks

    func loadBlocks(for date: Date) async {
        let dateString = formatDate(date)

        // Load categories if not loaded yet, or retry if we fell back to defaults
        if !categoriesLoaded || categoriesAreDefaults {
            await loadCategories()
        }

        guard dateString != currentDate else { return }

        currentDate = dateString
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Get authenticated database client
            let db = await supabaseDBAsync()

            // Fetch blocks for the date (RLS will filter by user_id automatically)
            let fetchedBlocks: [Block] = try await db
                .from("blocks")
                .select()
                .eq("date", value: dateString)
                .order("block_index")
                .execute()
                .value

            print("📥 Loaded \(fetchedBlocks.count) blocks from database for \(dateString)")
            for block in fetchedBlocks where block.label != nil {
                print("📥   Block \(block.blockIndex): label='\(block.label ?? "nil")', category='\(block.category ?? "nil")'")
            }

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
            print("Error loading blocks: \(error)")
        }
    }

    // MARK: - Reload Current Date

    func reloadBlocks() async {
        print("🔄 reloadBlocks() called, currentDate was: \(currentDate)")

        // Retry categories if we're stuck on defaults
        if categoriesAreDefaults {
            print("🔄 Categories are defaults, retrying load...")
            await loadCategories()
        }

        let savedDate = currentDate
        currentDate = "" // Force reload
        if let date = parseDate(savedDate) {
            print("🔄 Forcing reload for date: \(savedDate)")
            await loadBlocks(for: date)
        } else {
            print("🔄 Could not parse date: \(savedDate)")
        }
    }

    // MARK: - Load Blocks for Date Range (for overviews)

    func loadBlocksForDateRange(dates: [String], onlyWithActivity: Bool = false) async -> [Block] {
        guard !dates.isEmpty else { return [] }

        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("⚠️ No session available for loading blocks")
                return []
            }

            let userId = session.user.id.uuidString
            let startDate = dates.first!
            let endDate = dates.last!

            print("📊 Loading blocks for range: \(startDate) to \(endDate) (onlyWithActivity: \(onlyWithActivity))")

            var query = db
                .from("blocks")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDate)
                .lte("date", value: endDate)

            // For large date ranges, only fetch blocks with activity
            if onlyWithActivity {
                query = query.eq("status", value: "done")
            }

            let fetchedBlocks: [Block] = try await query
                .order("date")
                .order("block_index")
                .execute()
                .value

            print("📊 Loaded \(fetchedBlocks.count) blocks for date range")
            return fetchedBlocks
        } catch {
            print("Error loading blocks for date range: \(error)")
            return []
        }
    }

    // MARK: - Update Block

    func updateBlock(_ block: Block) async {
        await saveBlock(block)
    }

    // MARK: - Save Block

    func saveBlock(_ block: Block) async {
        do {
            // Get authenticated database client
            let db = await supabaseDBAsync()

            // Get current user session
            guard let session = try? await supabaseAuth.session else {
                print("❌ No session available for saving block")
                return
            }

            let userId = session.user.id.uuidString

            // First, check if a block already exists for this user/date/block_index
            // This is important because placeholder blocks have random IDs
            let existingBlocks: [Block] = try await db
                .from("blocks")
                .select()
                .eq("user_id", value: userId)
                .eq("date", value: block.date)
                .eq("block_index", value: block.blockIndex)
                .execute()
                .value

            // Use existing block's ID if found, otherwise use the provided ID
            let blockId = existingBlocks.first?.id ?? block.id

            // Create the block to save with the correct ID and userId
            let blockToSave = Block(
                id: blockId,
                userId: userId,
                date: block.date,
                blockIndex: block.blockIndex,
                isMuted: block.isMuted,
                isActivated: block.isActivated,
                category: block.category,
                label: block.label,
                note: block.note,
                status: block.status,
                progress: block.progress,
                breakProgress: block.breakProgress,
                runs: block.runs,
                activeRunSnapshot: block.activeRunSnapshot,
                segments: block.segments,
                usedSeconds: block.usedSeconds,
                createdAt: existingBlocks.first?.createdAt ?? ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )

            print("📝 Saving block \(blockToSave.blockIndex): id='\(blockToSave.id)', label='\(blockToSave.label ?? "nil")', category='\(blockToSave.category ?? "nil")', status=\(blockToSave.status)")
            print("📝   Existing block id from DB lookup: \(existingBlocks.first?.id ?? "none")")
            print("📝   Existing block label from DB lookup: \(existingBlocks.first?.label ?? "nil")")

            try await db
                .from("blocks")
                .upsert(blockToSave)
                .execute()

            // Update local state immediately
            if let index = blocks.firstIndex(where: { $0.id == blockToSave.id }) {
                print("✅ Found block by id at index \(index), old label: '\(blocks[index].label ?? "nil")'")
                blocks[index] = blockToSave
                print("✅ Updated local block by id at index \(index), new label: '\(blocks[index].label ?? "nil")'")
            } else if let index = blocks.firstIndex(where: { $0.blockIndex == blockToSave.blockIndex && $0.date == blockToSave.date }) {
                print("✅ Found block by blockIndex at index \(index), old label: '\(blocks[index].label ?? "nil")'")
                blocks[index] = blockToSave
                print("✅ Updated local block by blockIndex at index \(index), new label: '\(blocks[index].label ?? "nil")'")
            } else {
                print("⚠️ Could not find block in local state to update")
            }

            print("✅ Saved block \(blockToSave.blockIndex) successfully with label '\(blockToSave.label ?? "nil")'")
        } catch {
            self.error = error.localizedDescription
            print("Error saving block: \(error)")
        }
    }

    // MARK: - Load Categories

    func loadCategories() async {
        print("Starting to load categories...")

        do {
            // Get authenticated database client
            let db = await supabaseDBAsync()

            // Get user ID
            guard let session = try? await supabaseAuth.session else {
                print("⚠️ No session, using default categories")
                categories = Category.defaults
                categoriesLoaded = true
                categoriesAreDefaults = true
                return
            }

            print("Got database client, fetching profile for user \(session.user.id)...")

            // Categories are stored in profiles.custom_categories
            struct ProfileRow: Codable {
                let customCategories: [Category]?

                enum CodingKeys: String, CodingKey {
                    case customCategories = "custom_categories"
                }
            }

            let result: [ProfileRow] = try await db
                .from("profiles")
                .select("custom_categories")
                .eq("user_id", value: session.user.id.uuidString)
                .execute()
                .value

            print("📊 Parsed \(result.count) profile row(s)")

            if let profile = result.first {
                print("📊 Profile customCategories is \(profile.customCategories == nil ? "nil" : "present with \(profile.customCategories?.count ?? 0) items")")

                // Load categories
                if let customCats = profile.customCategories, !customCats.isEmpty {
                    categories = customCats
                    categoriesAreDefaults = false
                    print("✅ Loaded \(customCats.count) custom categories from Supabase")
                    // Log labels for each category
                    for cat in customCats {
                        print("   📋 \(cat.id): labels = \(cat.labels ?? [])")
                    }
                } else {
                    categories = Category.defaults
                    categoriesAreDefaults = true
                    print("⚠️ Using \(Category.defaults.count) default categories (customCategories was \(profile.customCategories == nil ? "nil" : "empty"))")
                }
            } else {
                categories = Category.defaults
                categoriesAreDefaults = true
                print("✅ Using \(Category.defaults.count) default categories (no profile row)")
            }

            for cat in categories {
                print("  - \(cat.label) (\(cat.id)) color: \(cat.color)")
            }
            categoriesLoaded = true

        } catch {
            // On error, use defaults (will retry on next loadBlocks call)
            print("❌ Error loading categories: \(error)")
            print("Using default categories as fallback (will retry)")
            categories = Category.defaults
            categoriesLoaded = true
            categoriesAreDefaults = true
        }
    }

    // MARK: - Update Category

    func updateCategory(categoryId: String, name: String, color: String) async {
        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("❌ No session available for updating category")
                return
            }

            // Update local categories first
            if let index = categories.firstIndex(where: { $0.id == categoryId }) {
                var updatedCategory = categories[index]
                updatedCategory.label = name
                updatedCategory.color = color
                categories[index] = updatedCategory
            }

            // Save all categories to profile using update
            try await db
                .from("profiles")
                .update(["custom_categories": categories])
                .eq("user_id", value: session.user.id.uuidString)
                .execute()

            print("✅ Updated category \(categoryId): name=\(name), color=\(color)")
        } catch {
            print("❌ Error updating category: \(error)")
        }
    }

    // MARK: - Favorite Labels

    func loadFavoriteLabels() async {
        guard !favoriteLabelsLoaded else { return }

        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("⚠️ No session, no favorite labels")
                favoriteLabelsLoaded = true
                return
            }

            struct ProfileFavorites: Codable {
                let favoriteLabels: [String]?

                enum CodingKeys: String, CodingKey {
                    case favoriteLabels = "favorite_labels"
                }
            }

            let result: [ProfileFavorites] = try await db
                .from("profiles")
                .select("favorite_labels")
                .eq("user_id", value: session.user.id.uuidString)
                .execute()
                .value

            if let profile = result.first, let labels = profile.favoriteLabels {
                favoriteLabels = labels
                print("✅ Loaded \(labels.count) favorite labels")
            }
            favoriteLabelsLoaded = true
        } catch {
            print("⚠️ Could not load favorite labels: \(error)")
            favoriteLabelsLoaded = true
        }
    }

    private func saveFavoriteLabels(_ labels: [String]) async {
        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("❌ No session for saving favorites")
                return
            }

            try await db
                .from("profiles")
                .update(["favorite_labels": labels])
                .eq("user_id", value: session.user.id.uuidString)
                .execute()

            print("✅ Saved \(labels.count) favorite labels")
        } catch {
            print("❌ Error saving favorite labels: \(error)")
        }
    }

    func toggleFavoriteLabel(_ label: String) async {
        var updatedLabels = favoriteLabels

        if let index = updatedLabels.firstIndex(of: label) {
            // Remove from favorites
            updatedLabels.remove(at: index)
            print("⭐ Removed '\(label)' from favorites")
        } else {
            // Add to favorites (max 30)
            if updatedLabels.count < 30 {
                updatedLabels.append(label)
                print("⭐ Added '\(label)' to favorites")
            } else {
                print("⚠️ Max 30 favorite labels reached")
                return
            }
        }

        // Update local state
        favoriteLabels = updatedLabels

        // Save to Supabase
        await saveFavoriteLabels(updatedLabels)
    }

    func addFavoriteLabel(_ label: String) async {
        guard !favoriteLabels.contains(label) else { return }
        guard favoriteLabels.count < 30 else {
            print("⚠️ Max 30 favorite labels reached")
            return
        }

        var updatedLabels = favoriteLabels
        updatedLabels.append(label)
        favoriteLabels = updatedLabels

        await saveFavoriteLabels(updatedLabels)
        print("✅ Added favorite label: \(label)")
    }

    func removeFavoriteLabel(_ label: String) async {
        guard let index = favoriteLabels.firstIndex(of: label) else { return }

        var updatedLabels = favoriteLabels
        updatedLabels.remove(at: index)
        favoriteLabels = updatedLabels

        await saveFavoriteLabels(updatedLabels)
        print("✅ Removed favorite label: \(label)")
    }

    // MARK: - Add Label to Category

    func addLabelToCategory(categoryId: String, label: String) async {
        print("📝 addLabelToCategory called: categoryId='\(categoryId)', label='\(label)'")

        // Find the category
        guard let index = categories.firstIndex(where: { $0.id == categoryId }) else {
            print("❌ Category '\(categoryId)' not found in categories: \(categories.map { $0.id })")
            return
        }

        var category = categories[index]
        var labels = category.labels ?? []
        print("📝 Current labels for \(categoryId): \(labels)")

        // Check if label already exists
        if labels.contains(label) {
            print("📝 Label '\(label)' already exists, skipping")
            return
        }

        // Add to front, max 20 labels per category
        labels.insert(label, at: 0)
        if labels.count > 20 {
            labels = Array(labels.prefix(20))
        }

        category.labels = labels
        categories[index] = category
        print("📝 Updated labels for \(categoryId): \(labels)")

        // Save to Supabase using update
        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("❌ No session for saving category labels")
                return
            }

            // Log what we're about to save
            print("📝 Saving categories to Supabase via update...")
            print("📝 Categories being saved:")
            for cat in categories {
                print("   - \(cat.id): labels = \(cat.labels ?? [])")
            }

            // Use update since profile row already exists
            try await db
                .from("profiles")
                .update(["custom_categories": categories])
                .eq("user_id", value: session.user.id.uuidString)
                .execute()

            print("✅ Update completed - added label '\(label)' to category '\(categoryId)'")
        } catch {
            print("❌ Error adding label to category: \(error)")
        }
    }

    // MARK: - Remove Label from Category

    func removeLabelFromCategory(categoryId: String, label: String) async {
        print("🗑️ removeLabelFromCategory called: categoryId='\(categoryId)', label='\(label)'")

        // Find the category
        guard let index = categories.firstIndex(where: { $0.id == categoryId }) else {
            print("❌ Category '\(categoryId)' not found")
            return
        }

        var category = categories[index]
        var labels = category.labels ?? []

        // Remove the label
        labels.removeAll { $0 == label }

        category.labels = labels
        categories[index] = category
        print("🗑️ Updated labels for \(categoryId): \(labels)")

        // Save to Supabase
        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("❌ No session for saving category labels")
                return
            }

            try await db
                .from("profiles")
                .update(["custom_categories": categories])
                .eq("user_id", value: session.user.id.uuidString)
                .execute()

            print("✅ Removed label '\(label)' from category '\(categoryId)'")
        } catch {
            print("❌ Error removing label from category: \(error)")
        }
    }

    // MARK: - Auto-Skip Logic

    func processAutoSkip(currentBlockIndex: Int, timerBlockIndex: Int?) async {
        let today = formatDate(Date())

        // Only process blocks for today
        guard currentDate == today else { return }

        print("🔄 Processing auto-skip for blocks before \(currentBlockIndex)")

        for block in blocks {
            // Only process past blocks
            guard block.blockIndex < currentBlockIndex else { continue }

            // Skip if already done or skipped
            guard block.status != .done && block.status != .skipped else { continue }

            // NEVER auto-skip night blocks (0-23) - they're a special section
            // Night blocks should only be skipped via activateBlockForTimer when someone
            // actually starts a timer in that section during the allotted time
            guard !nightBlocksRange.contains(block.blockIndex) else { continue }

            // Skip muted blocks (sleep blocks outside night range, if any)
            guard !block.isMuted else { continue }

            // Don't process the block that has an active timer
            if let timerBlock = timerBlockIndex, block.blockIndex == timerBlock {
                continue
            }

            // Check if block has any actual usage (real work data, not just metadata)
            let hasSegments = !block.segments.isEmpty
            let hasUsedSeconds = block.usedSeconds > 0
            let hasRuns = !(block.runs?.isEmpty ?? true)
            let hasSnapshot = block.activeRunSnapshot != nil
            // Only mark as done if there's REAL usage data (not just progress which could be stale)
            // Segments and usedSeconds are the most reliable indicators of actual work
            let hasRealUsage = hasSegments || hasUsedSeconds || hasRuns || hasSnapshot

            if hasRealUsage {
                // Has actual usage data - mark as done
                await markBlockDone(block)
            } else {
                // No real usage - skip it (preserve planned metadata like category/label)
                await markBlockSkipped(block)
            }
        }
    }

    private func markBlockDone(_ block: Block) async {
        var updatedBlock = block
        updatedBlock.status = .done
        // Preserve category and label

        print("✅ Auto-marking block \(block.blockIndex) as DONE")
        await saveBlock(updatedBlock)
    }

    private func markBlockSkipped(_ block: Block) async {
        var updatedBlock = block
        updatedBlock.status = .skipped
        // Preserve category and label (planned metadata)

        print("⏭️ Auto-skipping block \(block.blockIndex)")
        await saveBlock(updatedBlock)
    }

    // MARK: - Block Activation

    /// Night blocks range (midnight to 8am)
    private var nightBlocksRange: ClosedRange<Int> { 0...23 }

    /// Called when continuing/starting a timer on a block - handles muted block activation
    /// This will:
    /// 1. Unmute and activate the block being started (any muted block)
    /// 2. For night blocks: auto-skip all previous muted/unused night blocks
    func activateBlockForTimer(blockIndex: Int) async {
        let today = formatDate(Date())
        guard currentDate == today else { return }

        // Find the block being activated
        guard let block = blocks.first(where: { $0.blockIndex == blockIndex }) else { return }

        // If the block is muted, unmute it immediately in local state (removes moon icon instantly)
        if block.isMuted {
            if let localIdx = blocks.firstIndex(where: { $0.blockIndex == blockIndex }) {
                blocks[localIdx].isMuted = false
                blocks[localIdx].isActivated = true
            }
            var activatedBlock = block
            activatedBlock.isMuted = false
            activatedBlock.isActivated = true
            await saveBlock(activatedBlock)
            print("🌙 Activated muted block \(blockIndex)")
        }

        // Special handling for night blocks
        guard nightBlocksRange.contains(blockIndex) else { return }

        // Auto-activate ALL remaining muted night blocks (user is clearly in work mode)
        // and auto-skip previous unused ones
        for otherBlock in blocks {
            guard nightBlocksRange.contains(otherBlock.blockIndex) else { continue }
            guard otherBlock.blockIndex != blockIndex else { continue }
            guard otherBlock.isMuted else { continue }
            guard otherBlock.status != .done && otherBlock.status != .skipped else { continue }

            if otherBlock.blockIndex < blockIndex {
                // Previous night block - check for usage
                let hasUsage = !otherBlock.segments.isEmpty || otherBlock.usedSeconds > 0 || otherBlock.progress > 0

                if hasUsage {
                    // Has data - mark as done, not skipped
                    if let localIdx = blocks.firstIndex(where: { $0.blockIndex == otherBlock.blockIndex }) {
                        blocks[localIdx].status = .done
                        blocks[localIdx].isMuted = false
                        blocks[localIdx].isActivated = true
                    }
                    var doneBlock = otherBlock
                    doneBlock.status = .done
                    doneBlock.isMuted = false
                    doneBlock.isActivated = true
                    await saveBlock(doneBlock)
                    print("🌙 Auto-marked night block \(otherBlock.blockIndex) as DONE (has data)")
                } else {
                    // No usage - skip it
                    var skippedBlock = otherBlock
                    skippedBlock.status = .skipped
                    await saveBlock(skippedBlock)
                    print("🌙 Auto-skipped unused night block \(otherBlock.blockIndex)")
                }
            } else {
                // Future night block - activate it (remove moon) so user can freely use them
                if let localIdx = blocks.firstIndex(where: { $0.blockIndex == otherBlock.blockIndex }) {
                    blocks[localIdx].isMuted = false
                    blocks[localIdx].isActivated = true
                }
                var activatedBlock = otherBlock
                activatedBlock.isMuted = false
                activatedBlock.isActivated = true
                await saveBlock(activatedBlock)
                print("🌙 Auto-activated future night block \(otherBlock.blockIndex)")
            }
        }
    }

    // MARK: - Reset Today's Blocks

    func resetTodayBlocks() async {
        let today = formatDate(Date())

        print("🔄 Resetting all blocks for \(today)")

        for block in blocks where block.date == today {
            guard !block.isMuted else { continue }

            var resetBlock = block
            resetBlock.status = .idle
            resetBlock.progress = 0
            resetBlock.breakProgress = 0
            resetBlock.usedSeconds = 0
            resetBlock.segments = []
            resetBlock.runs = nil
            resetBlock.activeRunSnapshot = nil
            // Preserve category and label for re-planning

            await saveBlock(resetBlock)
        }

        print("✅ Reset complete")
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
