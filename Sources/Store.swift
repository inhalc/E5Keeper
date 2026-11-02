import Foundation

/// 简单文件存储：配置、密钥、统计都放在 ~/Library/Application Support/E5Keeper
final class Store {
    static let shared = Store()

    let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        dir = base.appendingPathComponent("E5Keeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private var configURL: URL { dir.appendingPathComponent("config.json") }
    private var secretsURL: URL { dir.appendingPathComponent("secrets.json") }
    private var statsURL: URL { dir.appendingPathComponent("stats.json") }

    // MARK: 配置

    func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return cfg
    }

    func save(config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    // MARK: 密钥

    func loadSecrets() -> Secrets {
        guard let data = try? Data(contentsOf: secretsURL),
              let s = try? JSONDecoder().decode(Secrets.self, from: data) else {
            return Secrets()
        }
        return s
    }

    func save(secrets: Secrets) {
        guard let data = try? JSONEncoder().encode(secrets) else { return }
        try? data.write(to: secretsURL, options: .atomic)
        // 只有自己可读
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
    }

    // MARK: 统计

    func loadStats() -> Stats {
        guard let data = try? Data(contentsOf: statsURL),
              let s = try? JSONDecoder().decode(Stats.self, from: data) else {
            return Stats()
        }
        return s
    }

    func save(stats: Stats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: statsURL, options: .atomic)
    }

    func resetStats() {
        try? FileManager.default.removeItem(at: statsURL)
    }
}
