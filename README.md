# MacPilot Native

MacPilot 是面向当前 Intel MacBook Pro 的原生 macOS 菜单栏工具。本目录是 SwiftUI/AppKit 实现；仓库根目录的 Tauri/Rust OpenTypeless 在语音迁移完成前继续作为行为与数据兼容参考。

## 当前阶段

当前版本已经提供：

- 单一菜单栏图标和无 Dock 常驻的 accessory 应用。
- `概览 / 风扇 / 工具 / 语音` 四标签结构。
- 独立的十二分类设置窗口。
- 真实 CPU、内存、启动卷容量、活动网络接口、实时上下行速率和连接风险摘要。
- 面板打开时每 1 秒刷新，关闭时每 15 秒刷新。
- Intel 双风扇真实转速、每台风扇验证后的最低/最高范围、预设与手动滑块。
- 受签名限制的特权助手、5 秒短租约、失联自动恢复和独立恢复工具。
- EventKit 会议提前 10 分钟火箭提醒，以及设置中的开关与测试入口。
- 省电、保持唤醒、锁屏、保持亮屏、清洁屏幕/键盘、深色模式、隐藏桌面、隐藏程序坞和清倒废纸篓快捷工具。
- OpenTypeless 原生语音链路：全局快捷键、录音电平、16 kHz 单声道转换、转写、AI 润色、自动粘贴和历史记录。
- GLM-ASR、OpenAI Whisper、Groq Whisper、SiliconFlow 和 Custom Whisper；密钥只保存在 macOS 钥匙串。
- OpenTypeless 设置、历史和词典的复制式一次性迁移；旧目录不会被修改或删除。
- 历史记录复制、重新粘贴、重新润色和删除。

Deepgram、AssemblyAI 和火山引擎豆包属于实时 WebSocket 转写，尚未在当前录音后文件转写架构中开放。界面不会把这三家显示为可用服务。

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

安装到“应用程序”目录（可选）：

```bash
pkill -x MacPilotApp || true
ditto build/MacPilot.app /Applications/MacPilot.app
open /Applications/MacPilot.app
```

首次使用语音时，macOS 会分别请求麦克风和辅助功能权限。麦克风用于录音；辅助功能只用于向当前输入框发送一次受约束的 `Command-V`。粘贴完成后会恢复原剪贴板；若用户期间复制了新内容，则不会覆盖新内容。

## 语音迁移与数据位置

- 旧数据源：`~/Library/Application Support/com.opentypeless.app`。
- MacPilot 语音数据库：`~/Library/Application Support/MacPilot/Voice.sqlite`。
- API Key：钥匙串服务 `com.huyida.macpilot.voice`。
- 迁移使用临时副本读取 JSON/SQLite/WAL，不修改旧目录；迁移标记保证重复启动不会重复导入。
- 当前实机迁移结果：58 条历史记录、0 个词典条目、1 条迁移标记。

## 回滚

1. 退出 MacPilot；如风扇处于手动模式，等待 5 秒租约自动恢复，或运行 `bash scripts/restore-fans-auto.sh`。
2. 重新打开 `/Applications/OpenTypeless.app`。旧设置、数据库和录音目录仍保留，可继续使用。
3. 如需恢复旧火箭提醒，重新启用此前保留的 RocketReminder LaunchAgent；避免与 MacPilot 同时启用，以免重复提醒。
4. 删除 MacPilot 不会删除 OpenTypeless 数据。若要删除 MacPilot 自己的历史或钥匙串项目，应先单独备份并明确操作。

## 当前发布检查

- `swift test`：全量通过。
- Debug 与 Release 构建：通过。
- App 与特权助手签名验证：通过。
- 实机启动：单一 `MacPilotApp` 进程保持运行。
- 启动日志：无 error/fault；钥匙串和迁移在后台执行。
- 语音迁移：实机完成且幂等，密钥存在性已验证但未输出密钥内容。
- 尚未完成：三家实时 WebSocket STT、Apple 公证、24 小时睡眠/唤醒浸泡测试，以及用户真人语音端到端验收。

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

## 风扇验证记录

验证机型：Intel `MacBookPro15,1`（记录不包含序列号）。

- AppleSMC 只读探测：2 台风扇。
- 左风扇验证范围：2160～5927 RPM。
- 右风扇验证范围：2000～5489 RPM。
- 本机风扇值格式：4 字节小端 IEEE-754 `flt`；同时保留传统 FPE2 兼容测试。
- 手动控制只允许 `FxTg` 与 `FxMd`；不接受任意 SMC 键。
- 助手断开、租约超时和显式恢复均测试为只执行一次自动模式恢复。
- 应急恢复：`bash scripts/restore-fans-auto.sh`。

首次选择非“系统自动”模式时 macOS 会请求管理员授权安装签名助手。退出或失联后，短租约到期会恢复 Apple 自动控制。

## 第二阶段开发状态

已实现：

- 十一项工具使用封闭枚举，外部不能提交任意可执行路径或参数。
- 进程型工具只有退出码为 0 才更新状态；保持唤醒与亮屏使用可精确释放、幂等关闭的 IOPM assertion。
- 清洁屏幕和清洁键盘具备倒计时；键盘会话需要辅助功能权限并始终放行 `⌃⌥⌘Esc`。
- RocketReminder 的 10 分钟决策、15 分钟扫描、1 分钟过时边界、重复会议去重和 JSON 存储已迁入。
- “会议火箭”已进入概览、工具和“日历与提醒”设置；开关关闭时取消 45 秒扫描，开启状态写入 UserDefaults。
- EventKit 只提取事件标识、开始时间和全天标记，不保存标题、地点、参会人、备注或会议链接。
- 保持唤醒与亮屏使用可精确释放的 IOPM assertion，退出应用时统一释放。
- 清洁键盘仅在辅助功能授权后拦截输入，并始终保留 `⌃⌥⌘Esc` 退出组合键。
- 清倒废纸篓必须二次确认；命令失败时按钮不会伪装成成功状态。

日历权限和火箭动画已经实机验证，旧 RocketReminder LaunchAgent 已安全停用并保留原文件以便回滚。
