import Foundation

enum GraphAPI {
    static let base = "https://graph.microsoft.com/v1.0"
    static let loginBase = "https://login.microsoftonline.com"
    static let scope = "offline_access https://graph.microsoft.com/.default"

    /// 专用会话：断网时等待网络恢复，而不是立刻抛错
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.waitsForConnectivity = true
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 90
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    /// 网络的瞬时故障：休眠唤醒、Wi-Fi 重连、DNS 抖动
    static func isTransient(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        switch e.code {
        case .networkConnectionLost, .timedOut, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .resourceUnavailable, .badServerResponse:
            return true
        default:
            return false
        }
    }

    /// 只读接口池。都挑轻量、对账号无副作用的查询。
    static let readEndpoints: [String] = [
        "/me",
        "/me/drive",
        "/me/drive/root",
        "/me/drive/root/children",
        "/me/drive/recent",
        "/me/drive/special/documents",
        "/me/mailFolders",
        "/me/mailFolders/inbox",
        "/me/messages?$top=5",
        "/me/mailFolders/inbox/messages?$top=5",
        "/me/outlook/masterCategories",
        "/me/mailboxSettings",
        "/me/events?$top=5",
        "/me/calendar",
        "/me/calendars",
        "/me/contacts?$top=5",
        "/me/contactFolders",
        "/me/memberOf?$top=5",
        "/me/licenseDetails",
        "/me/insights/trending",
        "/me/insights/used",
        "/me/insights/shared",
        "/me/onenote/notebooks",
        "/me/onenote/sections",
        "/me/planner/tasks",
        "/me/planner/plans",
        "/me/todo/lists",
        "/me/joinedTeams",
        "/me/settings",
        "/me/drive/root/search(q=%27a%27)",
        "/sites/root",
        "/drives",
        "/groups?$top=5",
        "/users?$top=5",
        "/organization",
        "/subscribedSkus"
    ]

    // MARK: - HTTP

    struct HTTPResult {
        var status: Int
        var data: Data
    }

    static func url(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: base + path)
    }

    static func get(_ path: String, token: String, retries: Int = 2) async throws -> HTTPResult {
        guard let u = url(path) else { throw SimpleError("非法 URL：\(path)") }
        var attempt = 0
        while true {
            do {
                var req = URLRequest(url: u)
                req.httpMethod = "GET"
                req.timeoutInterval = 30
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("E5Keeper/1.0", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return HTTPResult(status: code, data: data)
            } catch {
                attempt += 1
                if attempt > retries || !isTransient(error) || Task.isCancelled { throw error }
                let delay = attempt == 1 ? 2.0 : 5.0
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    static func put(_ path: String, token: String, body: Data, contentType: String) async throws -> HTTPResult {
        guard let u = url(path) else { throw SimpleError("非法 URL：\(path)") }
        var req = URLRequest(url: u)
        req.httpMethod = "PUT"
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResult(status: code, data: data)
    }

    static func delete(_ path: String, token: String) async throws -> HTTPResult {
        guard let u = url(path) else { throw SimpleError("非法 URL：\(path)") }
        var req = URLRequest(url: u)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResult(status: code, data: data)
    }

    /// 表单 POST（OAuth 用）
    static func formPost(_ fullURL: String, fields: [String: String]) async throws -> Data {
        guard let u = URL(string: fullURL) else { throw SimpleError("非法 URL") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        return data
    }

    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

struct SimpleError: LocalizedError {
    let msg: String
    init(_ msg: String) { self.msg = msg }
    var errorDescription: String? { msg }
}
