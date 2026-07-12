# MacPilot Native

MacPilot 是面向当前 Intel MacBook Pro 的原生 macOS 菜单栏工具。本目录是 SwiftUI/AppKit 实现；仓库根目录的 Tauri/Rust OpenTypeless 在语音迁移完成前继续作为行为与数据兼容参考。

## 当前阶段

第一阶段已经提供：

- 单一菜单栏图标和无 Dock 常驻的 accessory 应用。
- `概览 / 风扇 / 工具 / 语音` 四标签结构。
- 独立的十二分类设置窗口。
- 真实 CPU、内存、启动卷容量、活动网络接口、实时上下行速率和连接风险摘要。
- 面板打开时每 1 秒刷新，关闭时每 15 秒刷新。

风扇、系统工具、会议火箭和语音页面当前明确显示后续阶段，不呈现模拟成功状态。

## 构建与测试

```bash
cd /Users/huyida/USERPRO/code/macpilot-native/native-macos
swift test
swift build -c release
bash scripts/build-app.sh
codesign --verify --deep --strict build/MacPilot.app
open build/MacPilot.app
```

构建物：`/Users/huyida/USERPRO/code/macpilot-native/native-macos/build/MacPilot.app`

## 第一阶段验证记录

验证日期：2026-07-12

- Swift 自动化测试：16 项通过，0 项失败。
- Release 构建：通过。
- App Bundle plist：`plutil -lint` 通过。
- ad-hoc 代码签名：`codesign --verify --deep --strict` 通过。
- 运行验证：`MacPilotApp` 以单一 LSUIElement 进程运行，没有普通窗口和 Dock 图标。
- 面板关闭资源采样：30 次、每 10 秒一次；CPU 通常为 0.0%，15 秒采集时峰值 3.8%；RSS 从约 32 MB 完成首次框架加载后稳定在约 53 MB，最高约 54.5 MB。
- 面板打开资源采样：6 次、每 10 秒一次；首次渲染瞬时 CPU 19.7%，随后为 0.2%～1.4%；RSS 稳定在约 55 MB。
- 失败回退：自动化测试确认采集失败时保留最后一次有效快照并公开错误，不用零值伪装正常状态。

资源采样命令：

```bash
pid=$(pgrep -x MacPilotApp)
for i in $(seq 1 30); do ps -p "$pid" -o pid=,%cpu=,rss=; sleep 10; done
```

## 当前回滚方式

第一阶段尚未接管风扇、登录项、系统工具、日历或 OpenTypeless，因此退出 `MacPilotApp` 即可完全回滚，不会改变系统状态或旧应用数据。
