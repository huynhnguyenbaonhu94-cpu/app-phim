import Foundation
import Security

struct AccountUser: Codable, Identifiable, Equatable {
    let id: Int
    let name: String?
    let email: String?
    let role: String
}

struct AccountAuthResponse: Decodable {
    let user: AccountUser
    let token: String?
}

struct AccountMeResponse: Decodable {
    let user: AccountUser?
}

struct AccountDevice: Decodable, Identifiable, Equatable {
    let id: String
    let deviceName: String
    let deviceModel: String?
    let platform: String
    let ipAddress: String?
    let createdAt: String
    let lastSeenAt: String
    let online: Bool
    let current: Bool
}

struct CloudFavorite: Decodable, Identifiable {
    let id: Int
    let userId: Int
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let addedAt: String?
}

struct CloudHistory: Decodable, Identifiable {
    let id: Int
    let userId: Int
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let episodeSlug: String?
    let episodeName: String?
    let watchedSeconds: Int
    let durationSeconds: Int
    let lastWatchedAt: String?
}

struct AccountSessionResult: Decodable {
    let success: Bool
    let loggedOut: Bool?
}

enum AccountTokenStore {
    private static let account = "cinemora.session.token"
    private static var service: String { Bundle.main.bundleIdentifier ?? "app.cinemora" }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

func parseAccountDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}
