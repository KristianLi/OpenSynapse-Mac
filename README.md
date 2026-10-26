# OpenSynapse for Mac

[OpenSynapse](https://github.com/A1mAssist/OpenSynapse)（Windows）的 macOS 移植版：不装雷蛇官方软件，直接在 Mac 上控制雷蛇外设。原生 SwiftUI 窗口应用，附带菜单栏电量显示。

> 非官方项目，与 Razer Inc. 无关联。

## 支持范围

协议实现逐项移植自 OpenSynapse 源码（上游提交 `117af46`），设备目录与上游完全一致：

| 设备族 | 数量 | 可控制项 |
|---|---|---|
| OpenRazer 目录（鼠标 / 键盘 / 笔记本 / 配件） | 259 款 + 22 款本地扩展 | 电量、回报率（含 8K）、DPI、DPI 档位、休眠、低电量提醒、各灯区灯效与亮度、整键盘自定义颜色、滚轮模式/加速/智能滚轮、按键优化、HyperPolling 指示灯 |
| 协议 25 键盘（Huntsman V3、Pro Type 等） | 23 款 | 固件/序列号、电量、游戏模式、回报率、Chroma 灯效与亮度 |
| 协议 25 音频（Kraken、BlackShark V2、Barracuda、Nari、Nommo、Seiren 等） | 45 款 | 均衡器预设与 10/8 段、低音、麦克风静音/音量/降噪、音源、主动降噪 |
| Chroma 0x10 灯光配件（Aether 灯、底座、支架、ARGB 控制器等） | 40 款 | 灯效、颜色、亮度、电量 |
| Kraken 灯光 | 7 款 | 关闭、静态、光谱、单/双/三色呼吸、自定义 |
| BlackShark V3 Pro | 1 款 | 电量、充电、侧音、THX、降噪模式、游戏/聊天平衡 |
| Kraken V4 Pro 耳机（`0567`，本移植新增） | 1 款 | 电量、侧音、游戏/聊天平衡、降噪状态（只读）、9 灯 RGB |
| HID LampArray 灯光（如 Kraken V4 Pro 控制终端 `0568`） | 自动识别 | 颜色、亮度、关灯、恢复设备自带灯效 |

和上游一样，页面只显示该型号目录里声明、并且接口探测确认可用的控制；写入操作在可读回的设备上会“先读 → 写 → 回读校验 → 失败则恢复”。

**没有移植**（依赖 Windows 或雷蛇专有组件）：Blade 笔记本的风扇/性能/显卡切换、THX 音频原生组件、Windows 滤镜驱动、宏录制、Chroma REST、Philips Hue、蓝牙 BLE 协议 30。

## 实机验证

以下设备已在真机上验证（写入均为“改 → 回读 → 恢复原值”）：

| 设备 | 已验证 |
|---|---|
| Basilisk V4 Pro（有线 `00E2`） | 电量、DPI、DPI 档位、8000 Hz 回报率、休眠、低电量提醒、滚轮/标志亮度、灯效 |
| Basilisk V3（`0099`） | DPI、回报率、灯光、段落 / 无极滚轮切换 |
| Kraken V4 Pro 耳机（`0567`） | 电量、侧音、游戏/聊天平衡、LampArray 灯光 |
| Kraken V4 Pro 控制终端（`0568`） | LampArray 灯光 |

实机测试中发现并修正的问题：Basilisk V4 Pro 继承的旧式回报率命令会被拒绝（现自动改用 HyperPolling 命令）；V4 Pro 的段落/无极切换只能用物理按键；Kraken V4 Pro 有线连接时要用链路字节 `0x00`。

## 和 Windows 版的差异

- **通信方式**：默认用 IOKit 的 HID 特性报告（与 Windows 版相同）。如果打不开 HID 接口（键盘接口需要“输入监控”权限），会自动改用 USB 控制传输，也就是 OpenRazer 在 Linux 上用的通道，不需要额外权限。可在“设置”中固定某一种方式。
- 报告格式相同，只是 macOS 把报告 ID 0 单独传递，所以字节下标比上游 C# 代码少 1。

## 构建与运行

需要 macOS 14+ 和 Swift 6（Xcode 或 Command Line Tools 均可）。

```bash
scripts/build-app.sh          # 生成 dist/OpenSynapse.app（ad-hoc 签名）
open dist/OpenSynapse.app
```

开发时也可以直接 `swift run OpenSynapseMac`。

运行测试（只装了 Command Line Tools 时需要指定 Testing 框架路径）：

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F
```

测试移植了上游的协议不变量（DPI/回报率字节、灯效协议族路由、Kraken/BlackShark 帧格式等），并对目录里每个设备的每个灯光控制项都实际构造并发送一次请求（发给模拟设备）。

## 使用提示

- 应用首次打开时由于是 ad-hoc 签名，可能需要右键 →“打开”。
- 请先退出其他雷蛇控制软件（如 Razer macOS、Razer Synapse），避免两个程序同时操作同一设备。
- 没有设备时，可在“设置”里打开**演示模式**，用模拟设备预览所有页面。
- “诊断日志”页记录每条发出的命令和设备回复，也列出所有雷蛇 HID 接口，适配新设备时很有用。
- `OpenSynapse --snapshot <目录>` 会用演示设备把每个页面渲染成 PNG 后退出（加 `--real` 用真实设备，只读）。
- `OpenSynapse --probe` 只读扫描所有设备并打印完整诊断日志；加 `--write-test` 做可恢复的写入往返测试，加 `--lamp-test` 让 LampArray 灯光变红 3 秒后恢复。

## 项目结构

```
Sources/RazerUSB/        C：USB 控制传输（IOUSBDeviceInterface）
Sources/RazerCore/       协议、设备目录、能力解析、IOKit HID 传输、模拟设备
  Resources/*.json       OpenRazer 设备目录（来自 OpenSynapse）
Sources/OpenSynapseMac/  SwiftUI 应用
Tests/RazerCoreTests/    协议测试
```

## 许可

本项目源码采用 [MIT 许可](LICENSE)，并保留 OpenSynapse 原作者的版权声明（协议层是其 C# 代码的 Swift 移植）。

`Sources/RazerCore/Resources/` 下的设备目录数据派生自 [OpenRazer](https://github.com/openrazer/openrazer)，继续遵循 GPL-2.0-or-later。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目与 Razer Inc. 无关联，不包含任何雷蛇软件、驱动或固件。Razer 及相关产品名称为其各自所有者的商标，仅用于标明兼容的硬件。
