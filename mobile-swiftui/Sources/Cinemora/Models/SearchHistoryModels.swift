import Foundation

struct SearchHistoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let query: String
    let searchedAt: Date

    init(query: String, searchedAt: Date = Date()) {
        self.id = UUID()
        self.query = query
        self.searchedAt = searchedAt
    }
}
