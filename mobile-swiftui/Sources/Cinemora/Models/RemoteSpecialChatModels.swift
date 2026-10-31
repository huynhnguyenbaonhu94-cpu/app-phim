import Foundation

struct RemoteSpecialChatMessage: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let sender: String
    let text: String?
    let mediaUrl: String?
    let mediaType: String?
    let mediaWidth: Double?
    let mediaHeight: Double?
    let createdAt: String

    var isFromAdmin: Bool { sender == "admin" }
}

struct RemoteSpecialChatMedia: Decodable {
    let attachmentId: Int
    let mimeType: String
    let byteSize: Int
    let mediaUrl: String
}
