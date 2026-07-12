import AppKit
import MacPilotCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPilot 设置"
        window.minSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MacPilot 设置")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack {
                            Text(section.title)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 190)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text(selection.title).font(.title2.weight(.semibold))
                Text(selection.phaseDescription).foregroundColor(.secondary)
                if selection == .general {
                    SettingRow(title: "登录时启动", detail: "工具阶段开放登录项管理", control: "稍后开放")
                    SettingRow(title: "默认页面", detail: "点击菜单栏图标后显示", control: "概览")
                    SettingRow(title: "后台刷新", detail: "面板关闭后每 15 秒刷新", control: "已开启")
                } else if selection == .monitoring {
                    SettingRow(title: "面板刷新频率", detail: "面板打开时实时更新", control: "1 秒")
                    SettingRow(title: "后台刷新频率", detail: "降低常驻功耗", control: "15 秒")
                    SettingRow(title: "网络风险摘要", detail: "显示 VPN、代理和 Wi-Fi 加密依据", control: "已开启")
                } else {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "hammer.fill").font(.system(size: 34)).foregroundColor(.indigo)
                            Text(selection.phaseDescription).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingRow: View {
    let title: String
    let detail: String
    let control: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(control)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}
