import RazerCore
import SwiftUI

private func pidText(_ pid: UInt16) -> String { String(format: "1532:%04X", pid) }

// MARK: Keyboards (protocol 25)

struct KeyboardView: View {
    @Bindable var model: KeyboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.name, subtitle: L("键盘 · \(pidText(model.device.productId)) · 协议 25", "Keyboard · \(pidText(model.device.productId)) · Protocol 25"),
                           symbol: DeviceCategory.keyboard.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy || model.lighting.busy, reload: { await model.load() })
                StatusBanner(status: model.status ?? model.lighting.status, error: model.error ?? model.lighting.error)
                CardGrid {
                    Card(title: L("设备信息", "Device info"), symbol: "info.circle") {
                        InfoRow(label: L("型号", "Model"), value: model.device.name)
                        InfoRow(label: "USB ID", value: pidText(model.device.productId))
                        InfoRow(label: L("固件版本", "Firmware"), value: model.state.firmware ?? "—")
                        InfoRow(label: L("序列号", "Serial number"), value: model.state.serial ?? "—")
                        InfoRow(label: L("通信方式", "Connection"), value: model.device.endpoint.pathDescription)
                    }
                    if model.state.gameMode != nil || model.state.pollingRate != nil {
                        Card(title: L("性能", "Performance"), symbol: "speedometer") {
                            if model.state.pollingRate != nil {
                                Picker(L("回报率", "Polling rate"), selection: Binding(get: { model.pollingRate }, set: { value in
                                    Task { await model.applyPollingRate(value) }
                                })) {
                                    ForEach(Keyboard25Device.pollingRateOptions, id: \.self) { Text(verbatim: "\($0) Hz").tag($0) }
                                }
                            }
                            if model.state.gameMode != nil {
                                Toggle(L("游戏模式（禁用 Win/Cmd 等按键）", "Game mode (disables Win/Cmd and similar keys)"), isOn: Binding(get: { model.gameMode }, set: { value in
                                    model.gameMode = value
                                    Task { await model.applyGameMode() }
                                }))
                            }
                        }
                        .disabled(model.busy)
                    }
                    ChromaLightingCard(model: model.lighting)
                }
            }
            .pagePadding()
        }
    }
}

// MARK: Chroma lighting

struct ChromaLightingCard: View {
    @Bindable var model: ChromaModel

    var body: some View {
        Card(title: model.device.legacy ? L("灯效（0x0F 通道）", "Lighting (0x0F channel)") : L("灯效", "Lighting effect"), symbol: "sparkles") {
            Picker(L("效果", "Effect"), selection: $model.effect) {
                ForEach(model.device.supportedEffects) { Text($0.displayName).tag($0) }
            }
            if model.effect.colorCount >= 1 {
                RazerColorPicker(title: model.effect.colorCount > 1 ? L("颜色 1", "Colour 1") : L("颜色", "Colour"), color: $model.colors[0])
            }
            if model.effect.colorCount >= 2 {
                RazerColorPicker(title: L("颜色 2", "Colour 2"), color: $model.colors[1])
            }
            ApplyButton(L("应用灯效", "Apply Effect"), busy: model.busy) { await model.applyEffect() }
            if model.device.supportsBrightness {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("亮度", "Brightness"))
                        Spacer()
                        Text("\(Int(model.brightness))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $model.brightness.stepped(1), in: 0...100) { editing in
                        if !editing { Task { await model.applyBrightness() } }
                    }
                }
            }
        }
        .disabled(model.busy)
    }
}

struct ChromaView: View {
    @Bindable var model: ChromaModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.name,
                           subtitle: L("\(model.device.category.displayName) · \(pidText(model.device.productId)) · Chroma 0x10 通道", "\(model.device.category.displayName) · \(pidText(model.device.productId)) · Chroma 0x10 channel"),
                           symbol: model.device.category.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                CardGrid {
                    Card(title: L("设备信息", "Device info"), symbol: "info.circle") {
                        InfoRow(label: L("型号", "Model"), value: model.device.name)
                        InfoRow(label: "USB ID", value: pidText(model.device.productId))
                        InfoRow(label: L("固件版本", "Firmware"), value: model.state.firmware ?? "—")
                        InfoRow(label: L("序列号", "Serial number"), value: model.state.serial ?? "—")
                        InfoRow(label: L("通信方式", "Connection"), value: model.device.endpoint.pathDescription)
                    }
                    ChromaLightingCard(model: model)
                }
            }
            .pagePadding()
        }
    }
}

// MARK: Audio (protocol 25)

struct AudioView: View {
    @Bindable var model: AudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.name,
                           subtitle: L("\(model.device.category.displayName) · \(pidText(model.device.productId)) · 协议 25 音频", "\(model.device.category.displayName) · \(pidText(model.device.productId)) · Protocol 25 audio"),
                           symbol: model.device.category.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                CardGrid {
                    Card(title: L("设备信息", "Device info"), symbol: "info.circle") {
                        InfoRow(label: L("型号", "Model"), value: model.device.name)
                        InfoRow(label: "USB ID", value: pidText(model.device.productId))
                        InfoRow(label: L("固件版本", "Firmware"), value: model.state.firmware ?? "—")
                        InfoRow(label: L("通信方式", "Connection"), value: model.device.endpoint.pathDescription)
                        if model.state.batteryPercent != nil {
                            InfoRow(label: L("电量", "Battery"), value: "\(model.state.batteryPercent!)%" + (model.state.charging == true ? L("（充电中）", " (charging)") : ""))
                        }
                    }
                    if model.state.eqPreset != nil || model.state.eqBands != nil {
                        equalizerCard
                    }
                    if model.state.bass != nil {
                        Card(title: L("低音增强", "Bass boost"), symbol: "speaker.wave.3") {
                            LabeledSlider(title: L("强度", "Strength"), value: $model.bass, range: 0...100)
                            ApplyButton(busy: model.busy) { await model.applyBass() }
                        }
                    }
                    if model.state.micMuted != nil || model.state.micVolume != nil || model.state.noiseSuppression != nil {
                        microphoneCard
                    }
                    if model.state.audioSource != nil {
                        Card(title: L("音源", "Audio source"), symbol: "cable.connector") {
                            Picker(L("输入", "Input"), selection: Binding(get: { model.source }, set: { value in
                                model.source = value
                                Task { await model.applySource() }
                            })) {
                                ForEach(AudioSource.allCases.filter { $0 != .none }) { Text($0.displayName).tag($0) }
                            }
                            .disabled(model.busy)
                        }
                    }
                    if model.state.ancState != nil {
                        Card(title: L("主动降噪", "Active noise cancelling"), symbol: "ear") {
                            Picker(L("模式", "Mode"), selection: $model.ancState) {
                                ForEach(AncState.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if model.ancState == .on {
                                Stepper(L("强度 \(model.ancLevel)", "Strength \(model.ancLevel)"), value: $model.ancLevel, in: 0...10)
                            }
                            ApplyButton(busy: model.busy) { await model.applyAnc() }
                        }
                    }
                    if let lighting = model.lighting {
                        KrakenLightingCard(model: lighting)
                    }
                }
            }
            .pagePadding()
        }
    }

    private var equalizerCard: some View {
        Card(title: L("均衡器", "Equaliser"), symbol: "slider.vertical.3") {
            if model.state.eqPreset != nil {
                Picker(L("预设", "Preset"), selection: Binding(get: { model.preset }, set: { value in
                    model.preset = value
                    Task { await model.applyPreset() }
                })) {
                    ForEach(HeadsetAudioDevice.presets, id: \.value) { Text($0.name).tag($0.value) }
                }
                .disabled(model.busy)
            }
            if !model.bands.isEmpty {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(model.bands.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            Text("\(Int(model.bands[index]))").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            VerticalSlider(value: $model.bands[index])
                                .frame(height: 120)
                            Text(frequency(HeadsetAudioDevice.tenBandFrequencies[index])).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                ApplyButton(L("应用均衡器", "Apply EQ"), busy: model.busy) { await model.applyBands() }
            }
        }
    }

    private var microphoneCard: some View {
        Card(title: L("麦克风", "Microphone"), symbol: "mic") {
            if model.state.micMuted != nil {
                Toggle(L("静音", "Mute"), isOn: Binding(get: { model.micMuted }, set: { value in
                    model.micMuted = value
                    Task { await model.applyMicMute() }
                }))
            }
            if model.state.noiseSuppression != nil {
                Toggle(L("降噪", "Noise suppression"), isOn: Binding(get: { model.noiseSuppression }, set: { value in
                    model.noiseSuppression = value
                    Task { await model.applyNoiseSuppression() }
                }))
            }
            if model.state.micVolume != nil {
                LabeledSlider(title: L("音量", "Volume"), value: $model.micVolume, range: 0...100)
                ApplyButton(busy: model.busy) { await model.applyMicVolume() }
            }
        }
        .disabled(model.busy)
    }

    private func frequency(_ hertz: Int) -> String { hertz >= 1000 ? "\(hertz / 1000)k" : "\(hertz)" }
}

/// A slider rotated to vertical, for EQ bands.
struct VerticalSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { proxy in
            Slider(value: $value.stepped(1), in: 0...100)
                .frame(width: proxy.size.height)
                .rotationEffect(.degrees(-90))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 20)
    }
}

// MARK: Kraken

struct KrakenLightingCard: View {
    @Bindable var model: KrakenModel

    var body: some View {
        Card(title: L("耳机灯光", "Headset lighting"), symbol: "sparkles") {
            LightingEditor(settings: $model.settings, effects: model.device.model.effects)
            ApplyButton(L("应用灯效", "Apply Effect"), busy: model.busy) { await model.apply() }
            StatusBanner(status: model.status, error: model.error)
        }
    }
}

struct KrakenView: View {
    @Bindable var model: KrakenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.model.name, subtitle: L("耳机 · \(pidText(model.device.productId)) · 37 字节输出报告", "Headset · \(pidText(model.device.productId)) · 37-byte output report"),
                           symbol: DeviceCategory.headset.symbolName, battery: nil, charging: nil, busy: model.busy, reload: nil)
                Text(L("Kraken 的灯光通道只能写入，无法读回当前状态；音频、麦克风和 EQ 不在此通道上。", "The Kraken lighting channel is write-only, so the current state cannot be read back; audio, microphone and EQ are not on this channel."))
                    .font(.callout).foregroundStyle(.secondary)
                CardGrid {
                    KrakenLightingCard(model: model)
                }
            }
            .pagePadding()
        }
    }
}

// MARK: BlackShark V3 Pro

struct BlackSharkView: View {
    @Bindable var model: BlackSharkModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.name,
                           subtitle: L("耳机 · \(pidText(model.device.productId)) · \(model.device.wireless ? "2.4 GHz" : "有线")", "Headset · \(pidText(model.device.productId)) · \(model.device.wireless ? "2.4 GHz" : "Wired")"),
                           symbol: DeviceCategory.headset.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                CardGrid {
                    if model.state.sidetone != nil {
                        Card(title: L("侧音", "Sidetone"), symbol: "waveform") {
                            LabeledSlider(title: L("级别", "Level"), value: $model.sidetone, range: 0...15)
                            ApplyButton(busy: model.busy) { await model.applySidetone() }
                        }
                    }
                    if model.device.supportsThx, model.state.thx != nil {
                        Card(title: L("THX 空间音效", "THX Spatial Audio"), symbol: "person.wave.2") {
                            Toggle(L("启用", "Enable"), isOn: Binding(get: { model.thx }, set: { value in
                                model.thx = value
                                Task { await model.applyThx() }
                            }))
                            .disabled(model.busy)
                        }
                    }
                    if let mode = model.state.ancMode {
                        Card(title: L("降噪", "Noise suppression"), symbol: "ear") {
                            if model.device.supportsAncWrite {
                                Picker(L("模式", "Mode"), selection: $model.ancMode) {
                                    ForEach(BlackSharkAncMode.allCases) { Text($0.displayName).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                if model.ancMode == .anc {
                                    Stepper(L("强度 \(model.ancLevel)", "Strength \(model.ancLevel)"), value: $model.ancLevel, in: 1...4)
                                }
                                ApplyButton(busy: model.busy) { await model.applyAnc() }
                            } else {
                                InfoRow(label: L("当前模式", "Current mode"), value: mode.displayName)
                                Text(L("这款耳机只上报降噪模式、不上报强度，为避免改掉你的设置，这里只显示状态；请用耳机上的按键切换。", "This headset reports its noise-cancelling mode but not the level, so to avoid changing your setting it is shown read-only; use the buttons on the headset to switch."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.state.gameChat != nil {
                        Card(title: L("游戏 / 聊天平衡", "Game / chat balance"), symbol: "dial.medium") {
                            LabeledSlider(title: L("平衡", "Balance"), value: $model.gameChat, range: 0...20) { value in
                                value < 10 ? L("偏游戏 \(10 - Int(value))", "Game +\(10 - Int(value))") : value > 10 ? L("偏聊天 \(Int(value) - 10)", "Chat +\(Int(value) - 10)") : L("居中", "Centred")
                            }
                            ApplyButton(busy: model.busy) { await model.applyGameChat() }
                        }
                    }
                    if let lighting = model.lighting {
                        LampArrayCard(model: lighting)
                    }
                }
            }
            .pagePadding()
        }
    }
}

// MARK: Unavailable

struct UnavailableView: View {
    let device: UnavailableDevice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: device.name, subtitle: L("\(pidText(device.productId)) · \(device.recognised ? "已识别，未能接管" : "未知型号")", "\(pidText(device.productId)) · \(device.recognised ? "Recognised, not controlled" : "Unknown model")"),
                           symbol: device.category?.symbolName ?? "questionmark.circle", battery: nil, charging: nil,
                           busy: false, reload: nil)
                Card(title: L("原因", "Reason"), symbol: "exclamationmark.triangle") {
                    Text(device.reason).textSelection(.enabled)
                    if device.recognised {
                        Text(L("请先退出其他可能占用设备的雷蛇控制程序，或在“设置”中切换通信方式后重新扫描。", "Quit other Razer software that may be using the device, or switch the connection in Settings, then rescan."))
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(L("这个型号不在 OpenSynapse 的设备列表里。可以把下面的接口信息提交给上游项目，帮助适配。", "This model is not in OpenSynapse's device list. You can send the interface details below to the upstream project to help add it."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Card(title: L("HID 接口", "HID interfaces"), symbol: "cable.connector.horizontal") {
                    ForEach(device.interfaces, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .pagePadding()
        }
    }
}

// MARK: HID LampArray

struct LampArrayCard: View {
    @Bindable var model: LampArrayModel

    var body: some View {
        Card(title: L("灯光（\(model.device.lampCount) 个灯）", "Lights (\(model.device.lampCount) lamps)"), symbol: "sparkles") {
            RazerColorPicker(title: L("颜色", "Colour"), color: $model.color)
            LabeledSlider(title: L("亮度", "Brightness"), value: $model.brightness, range: 0...100) { "\(Int($0))%" }
            HStack {
                Button(L("关灯", "Lights off")) { Task { await model.off() } }
                Button(L("恢复设备自带灯效", "Restore Device Effect")) { Task { await model.restoreDeviceEffect() } }
                    .help(L("把灯光交还给设备内存储的灯效（HID LampArray 自主模式）", "Hand the lights back to the effect stored on the device (HID LampArray autonomous mode)"))
                Spacer()
                Button(L("应用", "Apply")) { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.razer)
            }
            .disabled(model.busy)
            StatusBanner(status: model.status, error: model.error)
        }
    }
}

struct LampArrayView: View {
    @Bindable var model: LampArrayModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.name, subtitle: L("\(pidText(model.device.productId)) · HID LampArray 灯光", "\(pidText(model.device.productId)) · HID LampArray lighting"),
                           symbol: "lightbulb.led", battery: nil, charging: nil, busy: model.busy, reload: nil)
                Text(L("通过标准 HID LampArray（Windows“动态光效”使用的同一接口）控制灯光。设备不提供当前颜色的回读。", "Lighting is controlled through standard HID LampArray (the interface Windows Dynamic Lighting uses). The device does not report its current colour."))
                    .font(.callout).foregroundStyle(.secondary)
                CardGrid {
                    LampArrayCard(model: model)
                }
            }
            .pagePadding()
        }
    }
}
