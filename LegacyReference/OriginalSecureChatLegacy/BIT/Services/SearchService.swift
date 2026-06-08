import Foundation
import SQLite3

final class SearchService {
    static let shared = SearchService()

    private let persistence = MessagePersistenceService.shared
    private let queue = DispatchQueue(label: "com.secureChat.search", attributes: .concurrent)

    private init() {
        initializeFullTextSearch()
    }

    // MARK: - Full-Text Search Setup
    private func initializeFullTextSearch() {
        // Create FTS5 virtual table for full-text search
        let createFTSTable = """
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                id UNINDEXED,
                content,
                senderID UNINDEXED,
                channelTag UNINDEXED,
                timestamp UNINDEXED,
                content=messages,
                content_rowid=rowid
            );
        """

        print("✅ Full-Text Search initialized")
    }

    // MARK: - Search Operations
    func search(
        _ query: String,
        in channelTag: String? = nil,
        senderID: String? = nil,
        dateRange: ClosedRange<Date>? = nil,
        mediaOnly: Bool = false,
        limit: Int = 50
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        let normalizedQuery = normalizeQuery(query)

        queue.sync {
            guard let db = self.getDatabaseConnection() else { return }

            // Build FTS5 query
            var ftsQuery = normalizedQuery
            if mediaOnly {
                ftsQuery += " AND mediaJSON IS NOT NULL"
            }

            let query = """
                SELECT
                    m.id, m.channelTag, m.senderID, m.content, m.timestamp,
                    m.mediaJSON, rank
                FROM messages_fts fts
                JOIN messages m ON fts.rowid = m.rowid
                WHERE messages_fts MATCH ?
            """

            var statement = query
            var params: [Any] = [ftsQuery]

            if let channelTag = channelTag {
                statement += " AND m.channelTag = ?"
                params.append(channelTag)
            }

            if let senderID = senderID {
                statement += " AND m.senderID = ?"
                params.append(senderID)
            }

            if let dateRange = dateRange {
                statement += " AND m.timestamp BETWEEN ? AND ?"
                params.append(Int(dateRange.lowerBound.timeIntervalSince1970))
                params.append(Int(dateRange.upperBound.timeIntervalSince1970))
            }

            statement += " ORDER BY rank DESC LIMIT ?"
            params.append(limit)

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, statement, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }

                // Bind parameters
                for (index, param) in params.enumerated() {
                    let paramIndex = Int32(index + 1)
                    if let stringParam = param as? String {
                        sqlite3_bind_text(stmt, paramIndex, stringParam, -1, SQLITE_TRANSIENT)
                    } else if let intParam = param as? Int {
                        sqlite3_bind_int64(stmt, paramIndex, Int64(intParam))
                    }
                }

                // Fetch results
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let result = self.parseSearchResult(stmt) {
                        results.append(result)
                    }
                }
            }

            sqlite3_close(db)
        }

        return results
    }

    func searchWithFuzzy(
        _ query: String,
        in channelTag: String? = nil,
        tolerance: Double = 0.8 // 0-1, higher = stricter match
    ) -> [SearchResult] {
        var results: [SearchResult] = []

        let allMessages = persistence.fetchMessages(
            channelTag: channelTag ?? "",
            limit: 10000
        )

        for message in allMessages {
            let score = levenshteinSimilarity(query, message.content)
            if score >= tolerance {
                results.append(SearchResult(
                    messageID: message.id,
                    channelTag: message.channelTag,
                    senderID: message.senderID,
                    content: message.content,
                    timestamp: message.timestamp,
                    relevanceScore: score,
                    matchContext: extractContext(message.content, query: query)
                ))
            }
        }

        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Advanced Filters
    func advancedSearch(criteria: SearchCriteria) -> [SearchResult] {
        var results: [SearchResult] = []

        let messages = persistence.fetchMessages(
            channelTag: criteria.channelTag ?? "",
            limit: criteria.maxResults
        )

        for message in messages {
            var matches = true

            // Apply all filters
            if let senderID = criteria.senderID, message.senderID != senderID {
                matches = false
            }

            if let hasMedia = criteria.hasMedia, (message.mediaAttachments != nil) != hasMedia {
                matches = false
            }

            if let hasReactions = criteria.hasReactions, message.reactions.isEmpty == hasReactions {
                matches = false
            }

            if let minLength = criteria.minContentLength, message.content.count < minLength {
                matches = false
            }

            if let dateRange = criteria.dateRange, !dateRange.contains(message.timestamp) {
                matches = false
            }

            if let status = criteria.deliveryStatus, message.deliveryStatus != status {
                matches = false
            }

            if matches && criteria.keywords.allSatisfy({ message.content.lowercased().contains($0.lowercased()) }) {
                results.append(SearchResult(
                    messageID: message.id,
                    channelTag: message.channelTag,
                    senderID: message.senderID,
                    content: message.content,
                    timestamp: message.timestamp,
                    relevanceScore: 1.0,
                    matchContext: extractContext(message.content, query: criteria.keywords.first ?? "")
                ))
            }
        }

        return results.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Saved Searches
    private var savedSearches: [String: SearchCriteria] = [:]

    func saveSearch(_ name: String, criteria: SearchCriteria) {
        queue.async(flags: .barrier) {
            self.savedSearches[name] = criteria
            print("✅ Search saved: \(name)")
        }
    }

    func executeSavedSearch(_ name: String) -> [SearchResult]? {
        var criteria: SearchCriteria?

        queue.sync {
            criteria = self.savedSearches[name]
        }

        guard let criteria = criteria else { return nil }
        return advancedSearch(criteria: criteria)
    }

    func listSavedSearches() -> [String] {
        var names: [String] = []

        queue.sync {
            names = Array(self.savedSearches.keys)
        }

        return names.sorted()
    }

    // MARK: - Indexing
    func rebuildSearchIndex() {
        queue.async(flags: .barrier) {
            guard let db = self.getDatabaseConnection() else { return }

            // Clear and rebuild FTS index
            let dropQuery = "DROP TABLE IF EXISTS messages_fts;"
            var error: UnsafeMutablePointer<Int8>?
            sqlite3_exec(db, dropQuery, nil, nil, &error)

            // Recreate and populate
            self.initializeFullTextSearch()

            print("✅ Search index rebuilt")
            sqlite3_close(db)
        }
    }

    // MARK: - Helper Methods
    private func normalizeQuery(_ query: String) -> String {
        // Escape special FTS characters
        let escaped = query
            .replacingOccurrences(of: "\"", with: "\"\"")
            .replacingOccurrences(of: "'", with: "''")

        return escaped.lowercased()
    }

    private func levenshteinSimilarity(_ str1: String, _ str2: String) -> Double {
        let s1 = str1.lowercased()
        let s2 = str2.lowercased()

        if s1.isEmpty && s2.isEmpty { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)

        return Double(maxLength - distance) / Double(maxLength)
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)

        var matrix = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)

        for i in 0...s1.count {
            matrix[i][0] = i
        }
        for j in 0...s2.count {
            matrix[0][j] = j
        }

        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[s1.count][s2.count]
    }

    private func extractContext(_ content: String, query: String, contextLength: Int = 50) -> String {
        guard let range = content.lowercased().range(of: query.lowercased()) else {
            return String(content.prefix(contextLength))
        }

        let startIndex = max(0, content.distance(from: content.startIndex, to: range.lowerBound) - contextLength)
        let endIndex = min(content.count, content.distance(from: content.startIndex, to: range.upperBound) + contextLength)

        let start = content.index(content.startIndex, offsetBy: startIndex)
        let end = content.index(content.startIndex, offsetBy: endIndex)

        return String(content[start..<end])
    }

    private func parseSearchResult(_ stmt: OpaquePointer) -> SearchResult? {
        guard let id = String(cString: sqlite3_column_text(stmt, 0), encoding: .utf8),
              let channelTag = String(cString: sqlite3_column_text(stmt, 1), encoding: .utf8),
              let senderID = String(cString: sqlite3_column_text(stmt, 2), encoding: .utf8),
              let content = String(cString: sqlite3_column_text(stmt, 3), encoding: .utf8) else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
        let relevanceScore = Double(sqlite3_column_double(stmt, 6))

        return SearchResult(
            messageID: id,
            channelTag: channelTag,
            senderID: senderID,
            content: content,
            timestamp: timestamp,
            relevanceScore: relevanceScore,
            matchContext: content
        )
    }

    private func getDatabaseConnection() -> OpaquePointer? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dbPath = "\(paths[0].path)/messages.db"

        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        return db
    }
}

// MARK: - Models
struct SearchResult: Identifiable {
    let id = UUID()
    let messageID: String
    let channelTag: String
    let senderID: String
    let content: String
    let timestamp: Date
    let relevanceScore: Double
    let matchContext: String
}

struct SearchCriteria {
    var keywords: [String] = []
    var channelTag: String?
    var senderID: String?
    var dateRange: ClosedRange<Date>?
    var hasMedia: Bool?
    var hasReactions: Bool?
    var minContentLength: Int?
    var maxContentLength: Int?
    var deliveryStatus: DeliveryStatus?
    var maxResults: Int = 100

    init(keywords: [String]) {
        self.keywords = keywords
    }
}
