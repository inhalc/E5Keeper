import Foundation
import Combine
import AppKit

@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    // MARK: 对外状态

    @Published var config: Config
    @Published private(set) var stats: Stats
    @Published private(set) var state: RunState = .idle
    @Published private(set) var nextFire: Date?
    @Published private(set) var logs: [LogLine] = []
    @Published private(set) var deviceCode: DeviceCodeInfo?
    @Published private(set) var hasToken: Bool = false
    @Published private(set) var now = Date()
    @Published private(set) var busy = false

    // MARK: 内部

    private let store = Store.shared
    private var secrets: Secrets
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast
    private var loopTask: Task<Void, Never>?
    private var ticker: Timer?
    private var consecutiveFailures = 0

    private init() {
        config = store.loadConfig()
        stats = store.loadStats()
        secrets = store.loadSecrets()
        hasToken = !secrets.refreshToken.isEmpty

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t

        if config.autoStart && hasToken {
            start()
        }
    }

    // MARK: - 配置写入

    func updateConfig(_ mutate: (inout Config) -> Void) {
        var c = config
        mutate(&c)
        config = c
        store.save(config: c)
    }

    func updateSecrets(clientSecret: String? = nil, refreshToken: String? = nil) {
        if let v = clientSecret { secrets.clientSecret = v }
        if let v = refreshToken { secrets.refreshToken = v }
        store.save(secrets: secrets)
        hasToken = !secrets.refreshToken.isEmpty
    }

    var clientSecretValue: String { secrets.clientSecret }

    func clearToken() {
        stop()
        updateSecrets(refreshToken: "")
        accessToken = nil
        tokenExpiry = .distantPast
        state = .idle
        log(.warn, "已清除本地令牌")
    }

    // MARK: - 启停

    func start() {
        guard loopTask == nil else { return }
        guard hasToken else {
            state = .waitingLogin
            log(.warn, "还没有令牌，请先做一次设备代码登录，或粘贴 refresh_token")
            return
        }
        state = .running
        stats.startedAt = Date()
        log(.info, "开始运行，调用间隔 \(Int(config.minInterval))–\(Int(config.maxInterval)) 秒，每轮 \(config.callsPerRound) 次")
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        nextFire = nil
        if case .stopped = state {} else { state = .idle }
        log(.info, "已停止")
    }

    func toggle() {
        if loopTask == nil { start() } else { stop() }
    }

    var isRunning: Bool { loopTask != nil }

    // MARK: - 主循环

    private func runLoop() async {
        while !Task.isCancelled {
            await runRound()

            guard !Task.isCancelled else { break }

            let wait = nextWaitSeconds()
            nextFire = Date().addingTimeInterval(wait)
            log(.info, "休眠 \(formatDuration(wait))，下次 \(timeString(nextFire!))")
            await sleepTick(seconds: wait)
        }
        nextFire = nil
    }

    private func sleepTick(seconds: Double) async {
        var remaining = seconds
        while remaining > 0 && !Task.isCancelled {
            let step = min(1.0, remaining)
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            remaining -= step
        }
    }

    private func nextWaitSeconds() -> Double {
        var wait = Double.random(in: config.minInterval...max(config.minInterval, config.maxInterval))
        if config.workHoursOnly {
            let hours = Calendar.current.component(.hour, from: Date())
            let inWindow = config.workStart <= config.workEnd
                ? (hours >= config.workStart && hours < config.workEnd)
                : (hours >= config.workStart || hours < config.workEnd)
            if !inWindow {
                // 睡到下一个工作时段开始
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .day, .hour], from: Date())
                comps.hour = config.workStart
                var target = cal.date(from: comps) ?? Date()
                if target <= Date() { target = target.addingTimeInterval(86400) }
                wait = max(wait, target.timeIntervalSinceNow + 60)
            }
        }
        return wait
    }

    // MARK: - 一轮调用

    func runOnce() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await runRound()
    }

    private func runRound() async {
        do {
            let token = try await validToken()
            let picks = GraphAPI.readEndpoints.shuffled().prefix(max(1, config.callsPerRound))
            for path in picks {
                if Task.isCancelled { return }
                await callOne(path, token: token)
                let gap = Double.random(in: 1...3)
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
            if config.allowWrites {
                await writeRound(token: token)
            }
            stats.lastCallAt = Date()
            consecutiveFailures = 0
            store.save(stats: stats)
        } catch {
            stats.failed += 1
            stats.lastError = error.localizedDescription
            store.save(stats: stats)
            log(.err, "本轮失败：\(error.localizedDescription)")

            if case .waitingLogin = state { return }
            if isAuthError(error) {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    stop()
                    state = .stopped("连续鉴权失败，已自动暂停（防止账号被风控）")
                    log(.err, "连续 3 次鉴权失败，自动暂停。请检查 client_id / secret / 令牌是否过期")
                }
            }
        }
    }

    private func callOne(_ path: String, token: String) async {
        do {
            let r = try await GraphAPI.get(path, token: token)
            stats.calls += 1
            if (200...299).contains(r.status) {
                stats.ok += 1
                log(.ok, "GET \(path) → \(r.status) · \(byteSize(r.data.count))")
            } else {
                stats.failed += 1
                let brief = serverMessage(r.data)
                stats.lastError = "\(r.status) \(brief)"
                log(.warn, "GET \(path) → \(r.status) \(brief)")
                if r.status == 401 { accessToken = nil; tokenExpiry = .distantPast }
            }
        } catch {
            stats.calls += 1
            stats.failed += 1
            stats.lastError = error.localizedDescription
            log(.err, "GET \(path) → \(error.localizedDescription)")
        }
    }

    /// 可选：在 OneDrive 根目录建一个小文件再删掉，制造一次写操作
    private func writeRound(token: String) async {
        let name = "e5keeper-\(Int(Date().timeIntervalSince1970)).txt"
        let body = "e5keeper keep-alive \(Date())".data(using: .utf8) ?? Data()
        do {
            let putPath = "/me/drive/root:/\(name):/content"
            let put = try await GraphAPI.put(putPath, token: token, body: body, contentType: "text/plain")
            stats.calls += 1
            if (200...299).contains(put.status) {
                stats.ok += 1
                if let id = jsonString(put.data, key: "id") {
                    let del = try await GraphAPI.delete("/me/drive/items/\(id)", token: token)
                    stats.calls += 1
                    if (200...299).contains(del.status) { stats.ok += 1 }
                    log(.ok, "写入保活：建/删 \(name) → \(put.status)/\(del.status)")
                } else {
                    log(.ok, "写入保活：建 \(name) → \(put.status)")
                }
            } else {
                stats.failed += 1
                log(.warn, "写入保活失败 → \(put.status) \(serverMessage(put.data))")
            }
        } catch {
            stats.failed += 1
            log(.err, "写入保活失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 令牌

    private func validToken() async throws -> String {
        if let t = accessToken, Date() < tokenExpiry.addingTimeInterval(-60) {
            return t
        }
        return try await refreshAccessToken()
    }

    private var tenantValue: String {
        let t = config.tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "common" : t
    }

    private func tokenURL() -> String {
        "\(GraphAPI.loginBase)/\(GraphAPI.formEncode(tenantValue))/oauth2/v2.0/token"
    }

    @discardableResult
    func refreshAccessToken() async throws -> String {
        guard !secrets.refreshToken.isEmpty else {
            throw SimpleError("没有 refresh_token，请先登录")
        }
        guard !config.clientId.isEmpty else {
            throw SimpleError("还没填 client_id")
        }
        var fields: [String: String] = [
            "client_id": config.clientId,
            "grant_type": "refresh_token",
            "refresh_token": secrets.refreshToken,
            "scope": GraphAPI.scope
        ]
        if !secrets.clientSecret.isEmpty { fields["client_secret"] = secrets.clientSecret }

        let data = try await GraphAPI.formPost(tokenURL(), fields: fields)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let token = resp.access_token else {
            throw SimpleError(resp.errorDescription ?? resp.error ?? "换 token 失败")
        }
        accessToken = token
        tokenExpiry = Date().addingTimeInterval(Double(resp.expires_in ?? 3600))
        stats.lastTokenRefresh = Date()
        // refresh_token 会轮换，务必存新的
        if let rt = resp.refresh_token, rt != secrets.refreshToken, !rt.isEmpty {
            updateSecrets(refreshToken: rt)
            log(.info, "refresh_token 已轮换并保存")
        }
        log(.ok, "access_token 已更新，有效期 \(resp.expires_in ?? 0) 秒")
        return token
    }

    private func isAuthError(_ error: Error) -> Bool {
        let d = error.localizedDescription.lowercased()
        return d.contains("invalid_grant") || d.contains("aadsts") || d.contains("unauthorized")
            || d.contains("token") || d.contains("401")
    }

    // MARK: - 设备代码登录

    func beginDeviceCodeLogin() {
        guard !config.clientId.isEmpty else {
            log(.err, "请先填 client_id")
            return
        }
        Task {
            do {
                let url = "\(GraphAPI.loginBase)/\(GraphAPI.formEncode(tenantValue))/oauth2/v2.0/devicecode"
                let data = try await GraphAPI.formPost(url, fields: [
                    "client_id": config.clientId,
                    "scope": GraphAPI.scope
                ])
                let dc = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
                guard let code = dc.device_code, let userCode = dc.user_code else {
                    throw SimpleError(dc.errorDescription ?? "申请设备代码失败")
                }
                let info = DeviceCodeInfo(
                    deviceCode: code,
                    userCode: userCode,
                    verificationUri: dc.verification_uri ?? "https://microsoft.com/devicelogin",
                    interval: max(3, dc.interval ?? 5),
                    expiresAt: Date().addingTimeInterval(Double(dc.expires_in ?? 900))
                )
                deviceCode = info
                state = .waitingLogin
                // 自动复制 + 把设置窗口顶到最前，浏览器抢焦点后也能一眼看到
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(userCode, forType: .string)
                SettingsWindowController.shared.show()
                log(.info, "请在浏览器打开 \(info.verificationUri)，输入代码 \(userCode)（已复制到剪贴板）")
                openURL(info.verificationUri)
                await pollDeviceCode(info)
            } catch {
                log(.err, "设备代码登录失败：\(error.localizedDescription)")
                state = .idle
            }
        }
    }

    private func pollDeviceCode(_ info: DeviceCodeInfo) async {
        var interval = info.interval
        while Date() < info.expiresAt && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            do {
                var pollFields: [String: String] = [
                    "client_id": config.clientId,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "device_code": info.deviceCode
                ]
                if !secrets.clientSecret.isEmpty { pollFields["client_secret"] = secrets.clientSecret }
                let data = try await GraphAPI.formPost(tokenURL(), fields: pollFields)
                let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
                if let token = resp.access_token {
                    accessToken = token
                    tokenExpiry = Date().addingTimeInterval(Double(resp.expires_in ?? 3600))
                    if let rt = resp.refresh_token { updateSecrets(refreshToken: rt) }
                    deviceCode = nil
                    state = .idle
                    log(.ok, "登录成功，已保存 refresh_token")
                    if config.autoStart { start() }
                    return
                }
                if resp.error == "authorization_pending" { continue }
                if resp.error == "slow_down" { interval += 5; continue }
                if resp.error == "authorization_declined" {
                    log(.err, "你在浏览器里取消了授权")
                    break
                }
                log(.err, "登录失败：\(resp.errorDescription ?? resp.error ?? "未知错误")")
                break
            } catch {
                log(.err, "轮询失败：\(error.localizedDescription)")
                break
            }
        }
        deviceCode = nil
        if state == .waitingLogin { state = .idle }
    }

    // MARK: - 工具

    func log(_ level: LogLine.Level, _ text: String) {
        let line = LogLine(date: Date(), level: level, text: text)
        logs.append(line)
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }

    func clearLogs() { logs.removeAll() }

    func resetStats() {
        store.resetStats()
        stats = Stats()
    }

    var countdownText: String {
        guard let f = nextFire else { return isRunning ? "运行中" : "未运行" }
        let s = f.timeIntervalSince(now)
        if s <= 0 { return "即将调用" }
        return "下次 \(formatDuration(s))"
    }

    var statusText: String {
        switch state {
        case .idle: return isRunning ? "运行中" : "已暂停"
        case .running: return "运行中"
        case .waitingLogin: return "等待登录"
        case .stopped(let why): return why
        }
    }

    private func openURL(_ s: String) {
        guard let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    private func serverMessage(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return String(msg.prefix(120))
        }
        return ""
    }

    private func jsonString(_ data: Data, key: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj[key] as? String
    }

    private func byteSize(_ n: Int) -> String {
        if n > 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return "\(n) B"
    }

    func formatDuration(_ s: Double) -> String {
        let total = Int(s.rounded())
        if total >= 3600 { return "\(total / 3600) 小时 \((total % 3600) / 60) 分" }
        if total >= 60 { return "\(total / 60) 分 \(total % 60) 秒" }
        return "\(total) 秒"
    }

    func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}

// MARK: - OAuth 响应

struct TokenResponse: Decodable {
    var access_token: String?
    var refresh_token: String?
    var expires_in: Int?
    var error: String?
    var error_description: String?

    var errorDescription: String? { error_description }
}

struct DeviceCodeResponse: Decodable {
    var device_code: String?
    var user_code: String?
    var verification_uri: String?
    var expires_in: Int?
    var interval: Int?
    var error: String?
    var error_description: String?

    var errorDescription: String? { error_description }
}
