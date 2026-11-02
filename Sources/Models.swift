import Foundation

// MARK: - 配置（非敏感，存 UserDefaults / config.json）

struct Config: Codable, Equatable {
    var tenant: String = "common"
    var clientId: String = ""
    var allowWrites: Bool = false
    var minInterval: Double = 120      // 秒
    var maxInterval: Double = 480      // 秒
    var callsPerRound: Int = 2
    var autoStart: Bool = true
    var workHoursOnly: Bool = false
    var workStart: Int = 9
    var workEnd: Int = 23
}

// MARK: - 密钥（0600 权限单独存文件）

struct Secrets: Codable, Equatable {
    var clientSecret: String = ""
    var refreshToken: String = ""
}

// MARK: - 统计

struct Stats: Codable {
    var calls: Int = 0
    var ok: Int = 0
    var failed: Int = 0
    var lastCallAt: Date?
    var lastError: String?
    var lastTokenRefresh: Date?
    var startedAt: Date?
}

// MARK: - 日志

struct LogLine: Identifiable {
    enum Level: String {
        case info, ok, warn, err
    }

    let id = UUID()
    let date: Date
    let level: Level
    let text: String
}

// MARK: - 设备代码登录

struct DeviceCodeInfo {
    var deviceCode: String
    var userCode: String
    var verificationUri: String
    var interval: Int
    var expiresAt: Date
}

// MARK: - 运行状态

enum RunState: Equatable {
    case idle
    case running
    case waitingLogin
    case stopped(String)
}
