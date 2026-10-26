import RazerCore
import SwiftUI

private func pidText(_ pid: UInt16) -> String { String(format: "1532:%04X", pid) }

// MARK: Keyboards (protocol 25)

struct KeyboardView: View {
    @Bindable var model: KeyboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.name, subtitle: "键盘 · \(pidText(model.device.productId)) · 协议 25",
                           symbol: DeviceCategory.keyboard.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy || model.lighting.busy, reload: { await model.load() })
                StatusBanner(status: model.status ?? model.lighting.status, error: model.error ?? model.lighting.error)
                CardGrid {
                    Card(title: "设备信息", symbol: "info.circle") {
                        InfoRow(label: "型号", value: model.device.name)
                        InfoRow(label: "USB ID", value: pidText(model.device.productId))
                        InfoRow(label: "固件版本", value: model.state.firmware ?? "—")
                        InfoRow(label: "序列号", value: model.state.serial ?? "—")
                        InfoRow(label: "通信方式", value: model.device.endpoint.pathDescription)
                    }
                    if model.state.gameMode != nil || model.state.pollingRate != nil {
                        Card(title: "性能", symbol: "speedometer") {
                            if model.state.pollingRate != nil {
                                Picker("回报率", selection: Binding(get: { model.pollingRate }, set: { value in
                                    Task { await model.applyPollingRate(value) }
                                })) {
                                    ForEach(Keyboard25Device.pollingRateOptions, id: \.self) { Text(verbatim: "\($0) Hz").tag($0) }
                                }
                            }
                            if model.state.gameMode != nil {
                                Toggle("游戏模式（禁用 Win/Cmd 等按键）", isOn: Binding(get: { model.gameMode }, set: { value in
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
        Card(title: model.device.legacy ? "灯效（0x0F 通道）" : "灯效", symbol: "sparkles") {
            Picker("效果", selection: $model.effect) {
                ForEach(model.device.supportedEffects) { Text($0.displayName).tag($0) }
            }
            if model.effect.colorCount >= 1 {
                RazerColorPicker(title: model.effect.colorCount > 1 ? "颜色 1" : "颜色", color: $model.colors[0])
            }
            if model.effect.colorCount >= 2 {
                RazerColorPicker(title: "颜色 2", color: $model.colors[1])
            }
            ApplyButton("应用灯效", busy: model.busy) { await model.applyEffect() }
            if model.device.supportsBrightness {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("亮度")
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
                           subtitle: "\(model.device.category.displayName) · \(pidText(model.device.productId)) · Chroma 0x10 通道",
                           symbol: model.device.category.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                CardGrid {
                    Card(title: "设备信息", symbol: "info.circle") {
                        InfoRow(label: "型号", value: model.device.name)
                        InfoRow(label: "USB ID", value: pidText(model.device.productId))
                        InfoRow(label: "固件版本", value: model.state.firmware ?? "—")
                        InfoRow(label: "序列号", value: model.state.serial ?? "—")
                        InfoRow(label: "通信方式", value: model.device.endpoint.pathDescription)
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
                           subtitle: "\(model.device.category.displayName) · \(pidText(model.device.productId)) · 协议 25 音频",
                           symbol: model.device.category.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                CardGrid {
                    Card(title: "设备信息", symbol: "info.circle") {
                        InfoRow(label: "型号", value: model.device.name)
                        InfoRow(label: "USB ID", value: pidText(model.device.productId))
                        InfoRow(label: "固件版本", value: model.state.firmware ?? "—")
                        InfoRow(label: "通信方式", value: model.device.endpoint.pathDescription)
                        if model.state.batteryPercent != nil {
                            InfoRow(label: "电量", value: "\(model.state.batteryPercent!)%" + (model.state.charging == true ? "（充电中）" : ""))
                        }
                    }
                    if model.state.eqPreset != nil || model.state.eqBands != nil {
                        equalizerCard
                    }
                    if model.state.bass != nil {
                        Card(title: "低音增强", symbol: "speaker.wave.3") {
                            LabeledSlider(title: "强度", value: $model.bass, range: 0...100)
                            ApplyButton(busy: model.busy) { await model.applyBass() }
                        }
                    }
                    if model.state.micMuted != nil || model.state.micVolume != nil || model.state.noiseSuppression != nil {
                        microphoneCard
                    }
                    if model.state.audioSource != nil {
                        Card(title: "音源", symbol: "cable.connector") {
                            Picker("输入", selection: Binding(get: { model.source }, set: { value in
                                model.source = value
                                Task { await model.applySource() }
                            })) {
                                ForEach(AudioSource.allCases.filter { $0 != .none }) { Text($0.displayName).tag($0) }
                            }
                            .disabled(model.busy)
                        }
                    }
                    if model.state.ancState != nil {
                        Card(title: "主动降噪", symbol: "ear") {
                            Picker("模式", selection: $model.ancState) {
                                ForEach(AncState.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if model.ancState == .on {
                                Stepper("强度 \(model.ancLevel)", value: $model.ancLevel, in: 0...10)
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
        Card(title: "均衡器", symbol: "slider.vertical.3") {
            if model.state.eqPreset != nil {
                Picker("预设", selection: Binding(get: { model.preset }, set: { value in
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
                ApplyButton("应用均衡器", busy: model.busy) { await model.applyBands() }
            }
        }
    }

    private var microphoneCard: some View {
        Card(title: "麦克风", symbol: "mic") {
            if model.state.micMuted != nil {
                Toggle("静音", isOn: Binding(get: { model.micMuted }, set: { value in
                    model.micMuted = value
                    Task { await model.applyMicMute() }
                }))
            }
            if model.state.noiseSuppression != nil {
                Toggle("降噪", isOn: Binding(get: { model.noiseSuppression }, set: { value in
                    model.noiseSuppression = value
                    Task { await model.applyNoiseSuppression() }
                }))
            }
            if model.state.micVolume != nil {
                LabeledSlider(title: "音量", value: $model.micVolume, range: 0...100)
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
        Card(title: "耳机灯光", symbol: "sparkles") {
            LightingEditor(settings: $model.settings, effects: model.device.model.effects)
            ApplyButton("应用灯效", busy: model.busy) { await model.apply() }
            StatusBanner(status: model.status, error: model.error)
        }
    }
}

struct KrakenView: View {
    @Bindable var model: KrakenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.device.model.name, subtitle: "耳机 · \(pidText(model.device.productId)) · 37 字节输出报告",
                           symbol: DeviceCategory.headset.symbolName, battery: nil, charging: nil, busy: model.busy, reload: nil)
                Text("Kraken 的灯光通道只能写入，无法读回当前状态；音频、麦克风和 EQ 不在此通道上。")
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
                           subtitle: "耳机 · \(pidText(model.device.productId)) · \(model.device.wireless ? "2.4 GHz" : "有线")",
                           symbol: DeviceCategory.headset.symbolName, battery: model.state.batteryPercent,
                           charging: model.state.charging, busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                CardGrid {
                    if model.state.sidetone != nil {
                        Card(title: "侧音", symbol: "waveform") {
                            LabeledSlider(title: "级别", value: $model.sidetone, range: 0...15)
                            ApplyButton(busy: model.busy) { await model.applySidetone() }
                        }
                    }
                    if model.device.supportsThx, model.state.thx != nil {
                        Card(title: "THX 空间音效", symbol: "person.wave.2") {
                            Toggle("启用", isOn: Binding(get: { model.thx }, set: { value in
                                model.thx = value
                                Task { await model.applyThx() }
                            }))
                            .disabled(model.busy)
                        }
                    }
                    if let mode = model.state.ancMode {
                        Card(title: "降噪", symbol: "ear") {
                            if model.device.supportsAncWrite {
                                Picker("模式", selection: $model.ancMode) {
                                    ForEach(BlackSharkAncMode.allCases) { Text($0.displayName).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                if model.ancMode == .anc {
                                    Stepper("强度 \(model.ancLevel)", value: $model.ancLevel, in: 1...4)
                                }
                                ApplyButton(busy: model.busy) { await model.applyAnc() }
                            } else {
                                InfoRow(label: "当前模式", value: mode.displayName)
                                Text("这款耳机只上报降噪模式、不上报强度，为避免改掉你的设置，这里只显示状态；请用耳机上的按键切换。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.state.gameChat != nil {
                        Card(title: "游戏 / 聊天平衡", symbol: "dial.medium") {
                            LabeledSlider(title: "平衡", value: $model.gameChat, range: 0...20) { value in
                                value < 10 ? "偏游戏 \(10 - Int(value))" : value > 10 ? "偏聊天 \(Int(value) - 10)" : "居中"
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
                PageHeader(title: device.name, subtitle: "\(pidText(device.productId)) · \(device.recognised ? "已识别，未能接管" : "未知型号")",
                           symbol: device.category?.symbolName ?? "questionmark.circle", battery: nil, charging: nil,
                           busy: false, reload: nil)
                Card(title: "原因", symbol: "exclamationmark.triangle") {
                    Text(device.reason).textSelection(.enabled)
                    if device.recognised {
                        Text("请先退出其他可能占用设备的雷蛇控制程序，或在“设置”中切换通信方式后重新扫描。")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("这个型号不在 OpenSynapse 的设备列表里。可以把下面的接口信息提交给上游项目，帮助适配。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Card(title: "HID 接口", symbol: "cable.connector.horizontal") {
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
        Card(title: "灯光（\(model.device.lampCount) 个灯）", symbol: "sparkles") {
            RazerColorPicker(title: "颜色", color: $model.color)
            LabeledSlider(title: "亮度", value: $model.brightness, range: 0...100) { "\(Int($0))%" }
            HStack {
                Button("关灯") { Task { await model.off() } }
                Button("恢复设备自带灯效") { Task { await model.restoreDeviceEffect() } }
                    .help("把灯光交还给设备内存储的灯效（HID LampArray 自主模式）")
                Spacer()
                Button("应用") { Task { await model.apply() } }
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
                PageHeader(title: model.device.name, subtitle: "\(pidText(model.device.productId)) · HID LampArray 灯光",
                           symbol: "lightbulb.led", battery: nil, charging: nil, busy: model.busy, reload: nil)
                Text("通过标准 HID LampArray（Windows“动态光效”使用的同一接口）控制灯光。设备不提供当前颜色的回读。")
                    .font(.callout).foregroundStyle(.secondary)
                CardGrid {
                    LampArrayCard(model: model)
                }
            }
            .pagePadding()
        }
    }
}
