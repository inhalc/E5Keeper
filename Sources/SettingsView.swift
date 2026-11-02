import SwiftUI
import AppKit

struct SettingsView: View {
    var scrollable: Bool = true
    @ObservedObject private var engine = Engine.shared

    @State private var tenant = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var minInterval: Double = 120
    @State private var maxInterval: Double = 480
    @State private var callsPerRound = 2
    @State private var allowWrites = false
    @State private var workHoursOnly = false
    @State private var workStart = 9
    @State private var workEnd = 23
    @State private var autoStart = true

    var body: some View {
        Group {
            if scrollable {
                ScrollView { content }
            } else {
                content
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadFromEngine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            authSection
            scheduleSection
            statsSection
            logSection
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 28, trailing: 20))
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: engine.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "pause.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(engine.isRunning ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("E5Keeper")
                    .font(.system(size: 17, weight: .semibold))
                Text(engine.statusText + " · " + engine.countdownText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(engine.isRunning ? "暂停" : "开始") { engine.toggle() }
                .keyboardShortcut(.defaultAction)
            Button("立即一轮") { Task { await engine.runOnce() } }
                .disabled(!engine.hasToken || engine.busy)
        }
    }

    // MARK: 授权

    private var authSection: some View {
        card("1 · Azure 应用与登录") {
            VStack(alignment: .leading, spacing: 10) {
                labeled("租户（Tenant ID 或 xxx.onmicrosoft.com，留空用 common）") {
                    TextField("common", text: $tenant)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: tenant) { _, v in engine.updateConfig { $0.tenant = v } }
                }
                labeled("客户端 ID（Application client ID）") {
                    TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: clientId) { _, v in engine.updateConfig { $0.clientId = v } }
                }
                labeled("客户端密码（可选，公共客户端可留空）") {
                    SecureField("留空表示用公共客户端流", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: clientSecret) { _, v in engine.updateSecrets(clientSecret: v) }
                }

                HStack(spacing: 8) {
                    Button("设备代码登录") { engine.beginDeviceCodeLogin() }
                        .disabled(clientId.isEmpty)
                    Button("清除令牌") { engine.clearToken() }
                        .disabled(!engine.hasToken)
                    Spacer()
                    Label(engine.hasToken ? "已保存令牌" : "无令牌",
                          systemImage: engine.hasToken ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(engine.hasToken ? Color.green : Color.orange)
                }

                if let dc = engine.deviceCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("在浏览器打开 \(dc.verificationUri)，输入下面的代码（已自动复制，⌘V 粘贴）：")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Text(dc.userCode)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .textSelection(.enabled)
                            Button("复制") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(dc.userCode, forType: .string)
                            }
                            Button("打开登录页") {
                                if let u = URL(string: dc.verificationUri) { NSWorkspace.shared.open(u) }
                            }
                            Spacer()
                        }
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Text("提示：应用注册里要打开「允许公共客户端流」，并给 Microsoft Graph 委派权限后点「代表组织授予管理员同意」。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 调度

    private var scheduleSection: some View {
        card("2 · 调用节奏") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    HStack(spacing: 6) {
                        Text("最小间隔")
                        TextField("", value: Binding(
                            get: { Int(minInterval) },
                            set: { v in
                                minInterval = Double(min(max(v, 30), Int(maxInterval)))
                                engine.updateConfig { $0.minInterval = minInterval }
                            }), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("秒").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("最大间隔")
                        TextField("", value: Binding(
                            get: { Int(maxInterval) },
                            set: { v in
                                maxInterval = Double(max(min(v, 3600), Int(minInterval)))
                                engine.updateConfig { $0.maxInterval = maxInterval }
                            }), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("秒").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("每轮结束在「最小–最大」之间随机取一个值休眠，避免固定节奏。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Stepper("每轮调用 \(callsPerRound) 个接口",
                        value: Binding(get: { callsPerRound },
                                       set: { v in callsPerRound = v; engine.updateConfig { $0.callsPerRound = v } }),
                        in: 1...8)

                Toggle("允许写入（在 OneDrive 建一个临时文件再删掉）", isOn: Binding(
                    get: { allowWrites },
                    set: { v in allowWrites = v; engine.updateConfig { $0.allowWrites = v } }))
                Text("默认只做读取。写入更像真人操作，但会在网盘留下痕迹（程序会自己删）。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("只在指定时段运行", isOn: Binding(
                    get: { workHoursOnly },
                    set: { v in workHoursOnly = v; engine.updateConfig { $0.workHoursOnly = v } }))
                if workHoursOnly {
                    HStack {
                        Stepper("从 \(workStart):00", value: Binding(
                            get: { workStart },
                            set: { v in workStart = v; engine.updateConfig { $0.workStart = v } }), in: 0...23)
                        Stepper("到 \(workEnd):00", value: Binding(
                            get: { workEnd },
                            set: { v in workEnd = v; engine.updateConfig { $0.workEnd = v } }), in: 0...24)
                    }
                }

                Toggle("启动时自动开始", isOn: Binding(
                    get: { autoStart },
                    set: { v in autoStart = v; engine.updateConfig { $0.autoStart = v } }))
            }
        }
    }

    // MARK: 统计

    private var statsSection: some View {
        card("3 · 运行数据") {
            HStack(spacing: 24) {
                statItem("总调用", "\(engine.stats.calls)")
                statItem("成功", "\(engine.stats.ok)")
                statItem("失败", "\(engine.stats.failed)")
                statItem("上次调用", engine.stats.lastCallAt.map { engine.timeString($0) } ?? "—")
                Spacer()
                Button("清零") { engine.resetStats() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: 日志

    private var logSection: some View {
        card("4 · 日志") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("复制") {
                        let text = engine.logs.map { "[\(engine.timeString($0.date))] \($0.level.rawValue.uppercased()) \($0.text)" }
                            .joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .controlSize(.small)
                    Button("清空") { engine.clearLogs() }
                        .controlSize(.small)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(engine.logs.suffix(120)) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(engine.timeString(line.date))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(color(for: line.level))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 190)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: 组件

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
    }

    private func color(for level: LogLine.Level) -> Color {
        switch level {
        case .info: return .primary
        case .ok: return .green
        case .warn: return .orange
        case .err: return .red
        }
    }

    private func loadFromEngine() {
        let c = engine.config
        tenant = c.tenant
        clientId = c.clientId
        clientSecret = engine.clientSecretValue
        minInterval = c.minInterval
        maxInterval = c.maxInterval
        callsPerRound = c.callsPerRound
        allowWrites = c.allowWrites
        workHoursOnly = c.workHoursOnly
        workStart = c.workStart
        workEnd = c.workEnd
        autoStart = c.autoStart
    }
}
