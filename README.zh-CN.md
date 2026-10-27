# OpenSynapse for Mac

[English](README.md) · 简体中文

[OpenSynapse](https://github.com/A1mAssist/OpenSynapse)（Windows）的 macOS 移植版：不装雷蛇官方软件，直接在 Mac 上控制雷蛇外设。原生 SwiftUI 窗口应用，附带菜单栏电量显示。

> 非官方项目，与 Razer Inc. 无关联。

## 项目状态：早期版本，实测设备很少

协议代码覆盖了 OpenSynapse 的全部设备列表，但**只有第一张表里的设备在真机上测过**。其余设备都按上游代码实现，并通过了针对模拟设备的单元测试，但从没在 macOS 上接过实物。这些设备可能会有问题，欢迎[反馈测试结果](#帮忙测试设备)。

### 已在真机上验证

写入测试方式为：修改 → 回读 → 恢复原值。

| 设备 | 已验证的读取 | 已验证的写入 |
|---|---|---|
| Basilisk V4 Pro，有线（`1532:00E2`） | 电量、充电状态、固件、序列号、DPI、DPI 档位、回报率（8000 Hz）、休眠时间、低电量提醒、标志/滚轮亮度、按键设置 | DPI、回报率、标志/滚轮亮度、DPI 档位表、板载按键映射（14 个按键，普通层和 HyperShift 层） |
| Basilisk V3（`1532:0099`） | 固件、序列号、DPI、DPI 档位、回报率、亮度、滚轮模式 | 段落 / 无极滚轮模式 |
| Kraken V4 Pro 耳机，USB 线连接（`1532:0567`） | 电量、侧音、降噪模式、游戏/聊天平衡 | 侧音、游戏/聊天平衡、HID LampArray 灯光 |
| Kraken V4 Pro 经控制终端，2.4 GHz（`1532:0568`） | 电量、充电状态、侧音、降噪模式、游戏/聊天平衡 | 侧音、游戏/聊天平衡、HID LampArray 灯光（在 USB 连接下测试） |

另外，在两款 Basilisk 都连接的情况下，鼠标灯效也已在应用里手动确认可用。

测试中发现、并已在代码里处理的问题：

- Basilisk V4 Pro 从目录里的同类型号继承了旧式回报率命令，固件会拒绝；应用会检测到并改用 HyperPolling 命令。
- Basilisk V4 Pro 的段落 / 无极模式不能用软件设置（固件拒绝读和写），只能用滚轮后方的按键切换。
- Kraken V4 Pro 通过 USB 连接时在链路字节 `0x00` 上应答；2.4 GHz 下控制终端在 `0x80` 上转发给耳机。
- Basilisk V4 Pro 按键设置的回复里，表示“层”的字节会沿用上一次写入的值，所以校验只比对功能和数据。滚轮后方的模式键本身也是可映射的按键，出厂功能是“切换滚轮模式”。左键旁的 M1 边缘键是 `0x0E`（出厂功能：配置循环），侧面最前面的第三侧键是 `0x80`（出厂为禁用，因为它的 AI Prompt Master 功能由 Synapse 软件实现），这两个都是实际按键确认的。同一个编号在不同型号上是不同的按键（Basilisk V3 的 `0x0E` 是底部的配置切换键），所以按键名称按型号区分；其他鼠标只按出厂功能命名，不标注位置。
- Kraken V4 Pro 对 THX 写入只应答不生效，所以隐藏了 THX；降噪强度不上报，所以降噪只显示状态。

### 已实现但未测试

| 设备族 | 型号数 | 可控制项 |
|---|---|---|
| OpenRazer 目录（鼠标 / 键盘 / 笔记本 / 配件） | 259 款 + 22 款本地扩展 | 板载按键映射（鼠标能回答按键列表时）、电量、回报率（最高 8K）、DPI、DPI 档位、休眠、低电量提醒、各灯区灯效与亮度、整键盘颜色、滚轮模式/加速/智能滚轮、按键优化、HyperPolling 指示灯 |
| 协议 25 键盘（Huntsman V3、Pro Type 等） | 23 款 | 固件/序列号、电量、游戏模式、回报率、Chroma 灯效与亮度 |
| 协议 25 音频（Kraken、BlackShark V2、Barracuda、Nari、Nommo、Seiren 等） | 45 款 | 均衡器预设与 10/8 段、低音、麦克风静音/音量/降噪、音源、主动降噪 |
| Chroma 0x10 灯光配件（Aether 灯、底座、支架、ARGB 控制器等） | 40 款 | 灯效、颜色、亮度、电量 |
| Kraken 灯光（旧型号） | 7 款 | 关闭、静态、光谱、单/双/三色呼吸、自定义 |
| BlackShark V3 Pro | 1 款 | 电量、充电、侧音、THX、降噪、游戏/聊天平衡 |
| HID LampArray 灯光 | 自动识别 | 颜色、亮度、关灯、恢复设备自带灯效 |

即使在已验证的设备上，也还没测过：通过 2.4 GHz 接收器连接的无线鼠标、USB 控制传输这条备用通道（所有测试都走 HID）、需要“输入监控”权限的键盘。

和上游一样，页面只显示该型号目录里声明、并且在接口上确认能应答的控制项；固件拒绝读取的控制项会被隐藏。

**没有移植**（依赖 Windows 或雷蛇专有组件）：Blade 笔记本的风扇/性能/显卡切换、THX 音频原生组件、Windows 滤镜驱动、宏录制、Chroma REST、Philips Hue、蓝牙 BLE 协议 30。

## 和 Windows 版的差异

- **通信方式**：默认用 IOKit 的 HID 特性报告，与 Windows 版发送的报告相同。如果打不开 HID 接口（键盘接口需要“输入监控”权限），会自动改用 USB 控制传输，也就是 OpenRazer 在 Linux 上用的通道，不需要额外权限。可在“设置”中固定某一种方式。
- 报告格式相同，只是 macOS 把报告 ID 0 单独传递，所以字节下标比上游 C# 代码少 1。
- 只要鼠标能回答按键列表查询，就提供板载按键映射（上游只对它从中间件补充的型号开放）；普通层的左键被锁定，避免改掉后无法点击。
- 上游没有、本项目新增的部分：Kraken V4 Pro 及其控制终端、HID LampArray 灯光、对目录里用旧式命令的 8 kHz 鼠标自动改用 HyperPolling 回报率命令。

## 构建与运行

需要 macOS 14+ 和 Swift 6（Xcode 或 Command Line Tools 均可）。

```bash
scripts/build-app.sh
```

这会生成 ad-hoc 签名的 `dist/OpenSynapse.app`。开发时也可以直接运行 `swift run OpenSynapseMac`。

运行测试（只装了 Command Line Tools 时需要指定 Testing 框架路径）：

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F
```

测试移植了上游的协议不变量（DPI 与回报率字节、灯效协议族路由、Kraken 与 BlackShark 帧格式），并把目录里每个设备的每个灯光控制项都实际构造并发送给模拟设备。

## 使用提示

- 由于是 ad-hoc 签名，首次打开可能需要右键 →“打开”。
- 请先退出其他雷蛇控制软件（Razer Synapse、Razer macOS），避免两个程序同时操作同一设备。
- 没有设备时，可在“设置”里打开**演示模式**，用模拟设备预览所有页面。
- “诊断日志”页记录每条发出的命令和设备回复，并列出所有雷蛇 HID 接口。

## 帮忙测试设备

如果你有“未测试”列表里的设备，一份只读报告就很有帮助：

```bash
dist/OpenSynapse.app/Contents/MacOS/OpenSynapse --probe
```

它会扫描已连接的雷蛇设备，只用读取命令获取状态，打印诊断日志后退出，不会写入任何东西。请附上输出和型号提交 issue。**发帖前请删掉输出里的序列号。**

还有两个检查写入的选项，都会恢复原值：

- `--probe --write-test`：修改 DPI、回报率和亮度，回读后恢复。
- `--probe --lamp-test`：让 HID LampArray 灯光变红 3 秒，然后交还给设备自带灯效。

`--snapshot <目录>` 会用演示设备把每个页面渲染成 PNG（加 `--real` 改用已连接的设备，只读）。

## 项目结构

```
Sources/RazerUSB/        C：USB 控制传输（IOUSBDeviceInterface）
Sources/RazerCore/       协议、设备目录、能力解析、IOKit 传输、模拟设备
  Resources/*.json       OpenRazer 设备目录（OpenSynapse 打包的版本）
Sources/OpenSynapseMac/  SwiftUI 应用
Tests/RazerCoreTests/    协议测试
```

## 许可

本项目源码采用 [MIT 许可](LICENSE)，并保留 OpenSynapse 的版权声明，因为协议层是其 C# 代码的 Swift 移植。

`Sources/RazerCore/Resources/` 下的设备目录数据派生自 [OpenRazer](https://github.com/openrazer/openrazer)，继续遵循 GPL-2.0-or-later。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目与 Razer Inc. 无关联，不包含任何雷蛇软件、驱动或固件。Razer 及相关产品名称为其各自所有者的商标，仅用于标明兼容的硬件。
