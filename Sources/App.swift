import SwiftUI
import AppKit

@main
struct E5KeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var engine = Engine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            Label("E5Keeper", systemImage: engine.isRunning ? "arrow.triangle.2.circlepath" : "pause.circle")
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - App 生命周期

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > idx + 1 {
            Snapshot.render(to: CommandLine.arguments[idx + 1])
            return
        }
        let forced = CommandLine.arguments.contains("--settings")
        if forced || !Engine.shared.hasToken {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                SettingsWindowController.shared.show()
            }
        }
    }
}

// MARK: - 设置窗口（用 AppKit 管窗口，避免 scene 打开的坑）

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "E5Keeper · 设置"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 580, height: 720))
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 菜单栏内容

struct MenuView: View {
    @ObservedObject private var engine = Engine.shared

    var body: some View {
        Group {
            Text(engine.statusText)
            Text(engine.countdownText)
            Text("成功 \(engine.stats.ok) · 失败 \(engine.stats.failed)")

            if case .waitingLogin = engine.state, let dc = engine.deviceCode {
                Divider()
                Text("代码：\(dc.userCode)")
                Button("复制代码并打开登录页") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dc.userCode, forType: .string)
                    if let u = URL(string: dc.verificationUri) { NSWorkspace.shared.open(u) }
                }
            }

            Divider()

            Button(engine.isRunning ? "暂停" : "开始保活") {
                engine.toggle()
            }

            Button("立即调用一轮") {
                Task { await engine.runOnce() }
            }
            .disabled(!engine.hasToken || engine.busy)

            Divider()

            Button("设置…") {
                SettingsWindowController.shared.show()
            }

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
