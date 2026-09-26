import Foundation

struct CinemaAPI {
    static let shared = CinemaAPI()
    static let baseURL = URL(string: (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String) ?? "https://cungcapicloud.id.vn")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    static func absoluteURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    func home(page: Int = 1) async throws -> MoviePage {
        try await query("cinema.home", input: ["page": page])
    }

    func list(page: Int = 1, kind: String = "latest", category: String? = nil, country: String? = nil, year: Int? = nil) async throws -> MoviePage {
        var input: [String: Any] = ["page": page, "kind": kind]
        if let category, !category.isEmpty { input["category"] = category }
        if let country, !country.isEmpty { input["country"] = country }
        if let year { input["year"] = year }
        return try await query("cinema.list", input: input)
    }

    func search(_ keyword: String) async throws -> MoviePage {
        try await query("cinema.search", input: ["keyword": keyword, "page": 1])
    }

    func detail(slug: String) async throws -> Movie {
        try await query("cinema.detail", input: ["slug": slug])
    }

    func meta() async throws -> CatalogMeta {
        try await query("cinema.meta", input: nil)
    }

    private func query<T: Decodable>(_ procedure: String, input: [String: Any]?) async throws -> T {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/trpc/\(procedure)"
        if let input {
            let inputData = try JSONSerialization.data(withJSONObject: ["json": input], options: [.sortedKeys])
            components.queryItems = [URLQueryItem(name: "input", value: String(data: inputData, encoding: .utf8))]
        }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let root = try JSONSerialization.jsonObject(with: data)
        guard let envelope = root as? [String: Any] else { throw APIError.invalidResponse }
        if let error = envelope["error"] as? [String: Any],
           let message = (error["json"] as? [String: Any])?["message"] as? String {
            throw APIError.server(message)
        }
        let result = envelope["result"] as? [String: Any]
        let resultData = result?["data"] as? [String: Any]
        let payload = resultData?["json"] ?? resultData?["data"] ?? envelope
        guard JSONSerialization.isValidJSONObject(payload) else { throw APIError.invalidResponse }
        let decodedData = try JSONSerialization.data(withJSONObject: payload)
        do { return try JSONDecoder().decode(T.self, from: decodedData) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse
    case http(Int)
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Địa chỉ API không hợp lệ."
        case .invalidResponse: return "Máy chủ trả về dữ liệu chưa đúng định dạng."
        case .http(let code): return "Máy chủ phản hồi lỗi (\(code)). Vui lòng thử lại."
        case .server(let message): return message
        case .decoding(let message): return "Không đọc được dữ liệu phim: \(message)"
        }
    }
}
