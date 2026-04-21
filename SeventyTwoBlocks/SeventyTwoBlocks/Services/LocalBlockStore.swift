import Foundation

/// Saves blocks as JSON files on the phone so the app works offline.
/// One file per date in Documents/blocks/. The phone is the source of truth;
/// the cloud (Supabase) is synced when available.
final class LocalBlockStore: @unchecked Sendable {

    private let fileManager = FileManager.default

    private lazy var blocksDirectory: URL = {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("blocks", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - Dirty Dates (local saves that haven't reached the cloud)

    private let dirtyDatesKey = "localBlockStore_dirtyDates"

    var dirtyDates: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: dirtyDatesKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: dirtyDatesKey)
        }
    }

    func markDirty(date: String) {
        var dates = dirtyDates
        dates.insert(date)
        dirtyDates = dates
    }

    func clearDirty(date: String) {
        var dates = dirtyDates
        dates.remove(date)
        dirtyDates = dates
    }

    // MARK: - Save / Load

    func saveBlocks(_ blocks: [Block], for date: String) {
        let url = fileURL(for: date)
        do {
            let data = try encoder.encode(blocks)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ LocalBlockStore: failed to save blocks for \(date): \(error)")
        }
    }

    func loadBlocks(for date: String) -> [Block]? {
        let url = fileURL(for: date)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let blocks = try decoder.decode([Block].self, from: data)
            return blocks
        } catch {
            print("⚠️ LocalBlockStore: failed to read blocks for \(date): \(error)")
            return nil
        }
    }

    // MARK: - Merge

    /// Merge local and cloud blocks per-block. Work data always wins over no work data.
    /// When both or neither have work, the newer updatedAt timestamp wins.
    static func mergeBlocks(local: [Block], remote: [Block]) -> [Block] {
        let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.blockIndex, $0) })
        let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0.blockIndex, $0) })

        var merged: [Block] = []
        for index in 0..<72 {
            let localBlock = localDict[index]
            let remoteBlock = remoteDict[index]

            switch (localBlock, remoteBlock) {
            case let (l?, r?):
                merged.append(pickWinner(local: l, remote: r))
            case let (l?, nil):
                merged.append(l)
            case let (nil, r?):
                merged.append(r)
            case (nil, nil):
                // Shouldn't happen if both arrays are full, but safety
                merged.append(local.first { $0.blockIndex == index } ?? remote.first { $0.blockIndex == index }!)
            }
        }
        return merged
    }

    /// Pick the better version of a single block.
    /// Rule: actual work data beats no work data. Otherwise newer timestamp wins.
    private static func pickWinner(local: Block, remote: Block) -> Block {
        let localHasWork = local.usedSeconds > 0 || !local.segments.isEmpty
        let remoteHasWork = remote.usedSeconds > 0 || !remote.segments.isEmpty

        // Work data always wins over no work data
        if localHasWork && !remoteHasWork { return local }
        if remoteHasWork && !localHasWork { return remote }

        // Both have work or neither — newer timestamp wins
        // ISO8601 strings are lexicographically sortable
        return local.updatedAt >= remote.updatedAt ? local : remote
    }

    // MARK: - Categories Cache

    func saveCategories(_ categories: [Category]) {
        let url = categoriesFileURL
        do {
            let data = try encoder.encode(categories)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ LocalBlockStore: failed to save categories: \(error)")
        }
    }

    func loadCategories() -> [Category]? {
        let url = categoriesFileURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([Category].self, from: data)
        } catch {
            print("⚠️ LocalBlockStore: failed to read categories: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private var categoriesFileURL: URL {
        blocksDirectory.appendingPathComponent("categories.json")
    }

    private func fileURL(for date: String) -> URL {
        blocksDirectory.appendingPathComponent("blocks-\(date).json")
    }
}
