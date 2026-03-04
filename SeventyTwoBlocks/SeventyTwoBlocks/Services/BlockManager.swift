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

    var onBlocksChanged: (() -> Void)?
    var onCategoriesChanged: (() -> Void)?

    private var currentDate: String = ""
    private var categoriesLoaded = false
    private var categoriesAreDefaults = false  // Track if we fell back to defaults
    private var favoriteLabelsLoaded = false

    // MARK: - Load Blocks

    func loadBlocks(for date: Date) async {
        let dateString = formatDate(date)

        // Load categories if not loaded yet, or retry if we fell back to defaults
        if !categoriesLoaded || categoriesAreDefaults {
            categoriesLoaded = true  // Set immediately to prevent duplicate loads from parallel calls
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
            // Debug: log blocks with segments to verify visualFill is loaded correctly
            for block in fetchedBlocks where !block.segments.isEmpty {
                let segmentSeconds = block.segments.reduce(0) { $0 + $1.seconds }
                print("📥   Block \(block.blockIndex) has segments: \(block.segments.count) segs, \(segmentSeconds)s total, visualFill=\(String(format: "%.2f", block.visualFill)), status=\(block.status)")
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
            onBlocksChanged?()
        } catch {
            self.error = error.localizedDescription
            print("Error loading blocks: \(error)")
        }
    }

    // MARK: - Fetch Single Block from Remote

    /// Fetch a single block fresh from Supabase (bypasses local cache)
    /// Used for cross-device sync to check if another device has modified the block
    func fetchBlockFromRemote(blockIndex: Int, date: String) async -> Block? {
        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("⚠️ fetchBlockFromRemote: No session available")
                return nil
            }

            let userId = session.user.id.uuidString

            let fetchedBlocks: [Block] = try await db
                .from("blocks")
                .select()
                .eq("user_id", value: userId)
                .eq("date", value: date)
                .eq("block_index", value: blockIndex)
                .execute()
                .value

            if let block = fetchedBlocks.first {
                print("🌐 Fetched remote block \(blockIndex): status=\(block.status), segments=\(block.segments.count), updatedAt=\(block.updatedAt)")
                return block
            } else {
                print("🌐 No remote block found for index \(blockIndex) on \(date)")
                return nil
            }
        } catch {
            print("❌ fetchBlockFromRemote error: \(error)")
            return nil
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

    /// Load blocks using simple start/end date strings (more efficient for large ranges like yearly)
    func loadBlocksForRange(startDate: String, endDate: String, onlyWithActivity: Bool = false) async -> [Block] {
        do {
            let db = await supabaseDBAsync()

            guard let session = try? await supabaseAuth.session else {
                print("⚠️ No session available for loading blocks")
                return []
            }

            let userId = session.user.id.uuidString

            print("📊 Loading blocks for range: \(startDate) to \(endDate) (onlyWithActivity: \(onlyWithActivity))")

            var query = db
                .from("blocks")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDate)
                .lte("date", value: endDate)

            if onlyWithActivity {
                query = query.eq("status", value: "done")
            }

            let fetchedBlocks: [Block] = try await query
                .order("date")
                .order("block_index")
                .execute()
                .value

            print("📊 Loaded \(fetchedBlocks.count) blocks for range")
            return fetchedBlocks
        } catch {
            print("Error loading blocks for range: \(error)")
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

            // Resolve the correct block ID from local state (already loaded from DB).
            // Placeholder blocks have random IDs; if the block already exists in our
            // local array (loaded from DB), use that ID instead.
            let existingLocal = blocks.first(where: { $0.blockIndex == block.blockIndex && $0.date == block.date })
            let blockId = existingLocal?.id ?? block.id

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
                visualFill: block.visualFill,
                createdAt: block.createdAt,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )

            let segmentSeconds = blockToSave.segments.reduce(0) { $0 + $1.seconds }
            print("📝 Saving block \(blockToSave.blockIndex): id='\(blockToSave.id)', status=\(blockToSave.status), segments=\(blockToSave.segments.count) (\(segmentSeconds)s), visualFill=\(String(format: "%.2f", blockToSave.visualFill))")

            try await db
                .from("blocks")
                .upsert(blockToSave, onConflict: "user_id,date,block_index")
                .execute()

            // Update local state immediately
            if let index = blocks.firstIndex(where: { $0.id == blockToSave.id }) {
                blocks[index] = blockToSave
            } else if let index = blocks.firstIndex(where: { $0.blockIndex == blockToSave.blockIndex && $0.date == blockToSave.date }) {
                blocks[index] = blockToSave
            }

            onBlocksChanged?()
            print("✅ Saved block \(blockToSave.blockIndex) successfully")
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
        // Never write categories back to DB if we're using defaults (prevents data corruption)
        guard !categoriesAreDefaults else {
            print("⚠️ Skipping category update - categories are defaults, not saving to DB")
            return
        }

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

            // Notify listeners (triggers widget update)
            onCategoriesChanged?()
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

        // Never write categories back to DB if we're using defaults (prevents data corruption)
        guard !categoriesAreDefaults else {
            print("⚠️ Skipping label add - categories are defaults, not saving to DB")
            return
        }

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

        // Never write categories back to DB if we're using defaults (prevents data corruption)
        guard !categoriesAreDefaults else {
            print("⚠️ Skipping label remove - categories are defaults, not saving to DB")
            return
        }

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

    func processAutoSkip(currentBlockIndex: Int, timerBlockIndex: Int?, blocksWithTimerUsage: Set<Int> = []) async {
        let today = formatDate(Date())

        // Only process blocks for today
        guard currentDate == today else { return }

        // Get dayStartHour to determine logical day order
        // With dayStartHour = 7, the logical day order is: indices 21-71, then 0-20
        // So indices 0-20 are FUTURE blocks (end of day), not past blocks
        let dayStartHour = UserDefaults.standard.object(forKey: "dayStartHour") as? Int ?? 6
        let dayStartIndex = dayStartHour * 3

        // Convert a block index to its logical position in the day (0-71 where 0 = start of user's day)
        func logicalPosition(_ index: Int) -> Int {
            return (index - dayStartIndex + 72) % 72
        }

        let currentLogicalPos = logicalPosition(currentBlockIndex)

        print("🔄 Processing auto-skip for blocks before \(currentBlockIndex) (logical pos \(currentLogicalPos), dayStartIndex=\(dayStartIndex))")

        // PHASE 1: Update local state immediately (instant UI update)
        var blocksToSave: [Block] = []

        for i in blocks.indices {
            let block = blocks[i]

            // Only process past blocks - compare in logical day order, not raw index order
            let blockLogicalPos = logicalPosition(block.blockIndex)
            guard blockLogicalPos < currentLogicalPos else { continue }

            // Skip if already done or skipped
            guard block.status != .done && block.status != .skipped else { continue }

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

            var updatedBlock = block
            if hasRealUsage {
                // Has actual usage data - mark as done
                updatedBlock.status = .done
                let segmentSeconds = block.segments.reduce(0) { $0 + $1.seconds }
                print("✅ Auto-marking block \(block.blockIndex) as DONE - segments: \(block.segments.count), \(segmentSeconds)s")
            } else if !blocksWithTimerUsage.contains(block.blockIndex) {
                // No real usage AND wasn't used this session - skip it
                updatedBlock.status = .skipped
                print("⏭️ Auto-skipping block \(block.blockIndex)")
            } else {
                continue  // Had timer usage this session, leave as-is
            }

            // Update local state immediately
            blocks[i] = updatedBlock
            blocksToSave.append(updatedBlock)
        }

        // Notify UI of changes immediately
        if !blocksToSave.isEmpty {
            onBlocksChanged?()
        }

        // PHASE 2: Save to database in background (doesn't block UI)
        for block in blocksToSave {
            await saveBlockToDBOnly(block)
        }
    }

    /// Save block to database only (doesn't update local state - already done)
    private func saveBlockToDBOnly(_ block: Block) async {
        do {
            let db = await supabaseDBAsync()
            guard let session = try? await supabaseAuth.session else { return }

            let userId = session.user.id.uuidString
            let blockToSave = Block(
                id: block.id,
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
                visualFill: block.visualFill,
                createdAt: block.createdAt,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )

            try await db
                .from("blocks")
                .upsert(blockToSave, onConflict: "user_id,date,block_index")
                .execute()
        } catch {
            print("❌ Error saving block \(block.blockIndex) to DB: \(error)")
        }
    }


    // MARK: - Block Activation

    /// Night blocks - blocks BEFORE the user's day start hour
    /// e.g., dayStartHour=7 → night blocks are 0-20 (midnight to 6:40am)
    /// e.g., dayStartHour=6 → night blocks are 0-17 (midnight to 5:40am)
    /// Called when starting a timer on a block - marks block as activated (hides moon icon)
    /// and clears .planned status since the timer is starting
    func activateBlockForTimer(blockIndex: Int) async {
        let today = formatDate(Date())
        guard currentDate == today else { return }

        // Find the block being activated
        guard let block = blocks.first(where: { $0.blockIndex == blockIndex }) else { return }

        var needsSave = false
        var activatedBlock = block

        // Mark as activated (hides moon icon in Night segment)
        if !block.isActivated {
            activatedBlock.isActivated = true
            needsSave = true
        }

        // Clear .planned status since timer is starting
        if block.status == .planned {
            activatedBlock.status = .idle
            needsSave = true
            print("📋 Cleared .planned status for block \(blockIndex) — timer is starting")
        }

        if needsSave {
            if let localIdx = blocks.firstIndex(where: { $0.blockIndex == blockIndex }) {
                blocks[localIdx].isActivated = activatedBlock.isActivated
                blocks[localIdx].status = activatedBlock.status
            }
            await saveBlock(activatedBlock)
        }
    }

    // MARK: - Reset Today's Blocks

    func resetTodayBlocks() async {
        let today = formatDate(Date())

        print("🔄 Resetting all blocks for \(today)")

        for block in blocks where block.date == today {
            var resetBlock = block
            resetBlock.isActivated = false  // Reset activation state (shows moon again in Night segment)
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
        return Block(
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
