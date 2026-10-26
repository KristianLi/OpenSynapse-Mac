import RazerCore
import SwiftUI

struct OpenRazerView: View {
    @Bindable var model: OpenRazerModel

    private var definition: DeviceDefinition { model.device.definition }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    title: definition.displayName,
                    subtitle: "\(definition.category.displayName) · \(definition.productIdText) · OpenRazer 协议",
                    symbol: definition.category.symbolName,
                    battery: model.state.batteryPercent, charging: model.state.charging,
                    busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                if !model.loaded {
                    ProgressView("正在读取设备…").frame(maxWidth: .infinity).padding(40)
                } else {
                    CardGrid {
                        infoCard
                        if model.has(.pollingRateWrite) || model.has(.dpiWrite) || model.has(.dpiRead) || model.has(.pollingRateRead) {
                            performanceCard
                        }
                        if model.device.has(.scrollModeWrite) || model.has(.scrollAccelerationWrite) || model.has(.smartReelWrite) {
                            scrollCard
                        }
                        if model.has(.dpiStagesRead) || model.has(.dpiStagesWrite) {
                            stagesCard
                        }
                        if model.has(.batteryRead) || model.has(.idleTimeoutWrite) || model.has(.lowBatteryThresholdWrite) {
                            powerCard
                        }
                        if !model.effectZones.isEmpty {
                            lightingCard
                        }
                        if !model.brightnessZones.isEmpty {
                            brightnessCard
                        }
                        if model.device.supportsMatrixFrames {
                            matrixCard
                        }
                        if model.has(.keyswitchOptimizationWrite) || model.has(.keyswitchOptimizationRead) {
                            keyswitchCard
                        }
                        if model.has(.hyperPollingIndicatorWrite) {
                            hyperPollingCard
                        }
                    }
                }
            }
            .pagePadding()
        }
    }

    private var infoCard: some View {
        Card(title: "设备信息", symbol: "info.circle") {
            InfoRow(label: "型号", value: definition.displayName)
            InfoRow(label: "USB ID", value: definition.productIdText)
            InfoRow(label: "固件版本", value: model.state.firmware ?? "—")
            InfoRow(label: "序列号", value: model.state.serial ?? "—")
            InfoRow(label: "通信方式", value: model.device.endpoint.pathDescription)
            InfoRow(label: "HID 接口", value: model.device.endpoint.interface.usageText)
            if let matrix = definition.matrixDimensions {
                InfoRow(label: "灯光矩阵", value: "\(matrix.rows) 行 × \(matrix.columns) 列")
            }
            InfoRow(label: "可用控制", value: "\(model.device.capabilities.count) 项")
        }
    }

    private var performanceCard: some View {
        Card(title: "性能", symbol: "speedometer") {
            pollingRow
            if model.has(.dpiWrite) {
                Divider()
                dpiEditor
            } else if let dpi = model.state.dpi {
                InfoRow(label: "DPI", value: "\(dpi.x) × \(dpi.y)")
            }
        }
    }

    @ViewBuilder private var pollingRow: some View {
        if model.has(.pollingRateWrite) {
            let selection = Binding<Int>(get: { model.pollingRate }, set: { value in
                Task { await model.applyPollingRate(value) }
            })
            Picker("回报率", selection: selection) {
                ForEach(model.device.pollingRateOptions, id: \.self) { (rate: Int) in
                    Text(verbatim: "\(rate) Hz").tag(rate)
                }
            }
            .disabled(model.busy)
        } else if model.has(.pollingRateRead) {
            InfoRow(label: "回报率", value: model.state.pollingRate.map { "\($0) Hz" } ?? "—")
        }
    }

    @ViewBuilder private var dpiEditor: some View {
        let maximum = Double(model.device.maximumDpi)
        Toggle("X / Y 轴 DPI 相同", isOn: $model.dpiLinked)
        DpiField(title: model.dpiLinked ? "DPI" : "X 轴 DPI", value: $model.dpiX, maximum: maximum)
        if !model.dpiLinked {
            DpiField(title: "Y 轴 DPI", value: $model.dpiY, maximum: maximum)
        }
        ApplyButton("应用 DPI", busy: model.busy) { await model.applyDpi() }
    }

    private var stagesCard: some View {
        Card(title: "DPI 档位", symbol: "slider.horizontal.3") {
            if model.stages.isEmpty {
                Text("设备没有返回档位表").foregroundStyle(.secondary)
            }
            ForEach(Array(model.stages.enumerated()), id: \.offset) { index, stage in
                HStack(spacing: 8) {
                    Button {
                        model.activeStage = UInt8(index + 1)
                    } label: {
                        Image(systemName: Int(model.activeStage) == index + 1 ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Int(model.activeStage) == index + 1 ? .razer : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("设为当前档位")
                    Text("档位 \(index + 1)").frame(width: 52, alignment: .leading)
                    TextField("X", value: Binding(get: { model.stages[index].x }, set: { model.stages[index].x = $0 }),
                              format: .number.grouping(.never))
                        .frame(width: 70)
                    Text("×").foregroundStyle(.secondary)
                    TextField("Y", value: Binding(get: { model.stages[index].y }, set: { model.stages[index].y = $0 }),
                              format: .number.grouping(.never))
                        .frame(width: 70)
                    Spacer()
                    Button(role: .destructive) { model.removeStage(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .disabled(model.stages.count <= 1)
                }
                .textFieldStyle(.roundedBorder)
            }
            if model.has(.dpiStagesWrite) {
                HStack {
                    Button("添加档位", systemImage: "plus") { model.addStage() }
                        .disabled(model.stages.count >= 5)
                    Spacer()
                    Text("100 – \(model.device.maximumDpi)").font(.caption).foregroundStyle(.secondary)
                }
                ApplyButton("写入档位", busy: model.busy) { await model.applyStages() }
            }
        }
    }

    private var powerCard: some View {
        Card(title: "电源", symbol: "battery.75percent") {
            if model.has(.batteryRead) {
                InfoRow(label: "电量", value: model.state.batteryPercent.map { "\($0)%" } ?? "—")
                if model.has(.chargingRead) {
                    InfoRow(label: "充电", value: model.state.charging.map { $0 ? "正在充电" : "未充电" } ?? "—")
                }
            }
            if model.has(.idleTimeoutWrite) {
                Divider()
                LabeledSlider(title: "无操作后休眠", value: $model.idleMinutes, range: 1...15, step: 0.5) {
                    String(format: "%.1f 分钟", $0)
                }
                ApplyButton(busy: model.busy) { await model.applyIdle() }
            }
            if model.has(.lowBatteryThresholdWrite) {
                Divider()
                if let current = model.state.lowBatteryThreshold, ![5, 10, 15, 20, 25].contains(current) {
                    InfoRow(label: "设备当前低电量提醒", value: "\(current)%")
                }
                Picker("低电量提醒", selection: $model.lowBattery) {
                    ForEach([5, 10, 15, 20, 25], id: \.self) { Text("\($0)%").tag($0) }
                }
                ApplyButton(busy: model.busy) { await model.applyLowBattery() }
            }
        }
    }

    private var lightingCard: some View {
        Card(title: "灯效", symbol: "sparkles") {
            let zones = model.effectZones
            if zones.count > 1 {
                Picker("灯区", selection: $model.lightingZone) {
                    ForEach(zones, id: \.zone) { Text($0.zone.displayName).tag($0.zone) }
                }
            }
            if let caps = model.device.lightingZones[model.lightingZone], model.lighting[model.lightingZone] != nil {
                let binding = Binding(get: { model.lighting[model.lightingZone]! }, set: { model.lighting[model.lightingZone] = $0 })
                LightingEditor(settings: binding, effects: caps.orderedEffects)
                ApplyButton("应用灯效", busy: model.busy) { await model.applyLighting() }
            }
        }
    }

    private var brightnessCard: some View {
        Card(title: "亮度", symbol: "sun.max") {
            ForEach(model.brightnessZones, id: \.zone) { caps in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(caps.zone.displayName)
                        Spacer()
                        Text("\(Int((model.brightness[caps.zone] ?? 255) / 255 * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { model.brightness[caps.zone] ?? 255 }, set: { model.brightness[caps.zone] = $0 }),
                           in: 0...255) { editing in
                        if !editing { Task { await model.applyBrightness(caps.zone) } }
                    }
                    .disabled(model.busy)
                }
            }
            Text("松开滑块即写入设备").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var matrixCard: some View {
        Card(title: "逐键灯光", symbol: "keyboard.badge.ellipsis") {
            Text("把整块灯光矩阵设为同一颜色（写入自定义帧）。").font(.callout).foregroundStyle(.secondary)
            RazerColorPicker(title: "颜色", color: $model.matrixColor)
            ApplyButton("填充全部按键", busy: model.busy) { await model.applyMatrixColor() }
        }
    }

    private var scrollCard: some View {
        Card(title: "滚轮", symbol: "computermouse") {
            if model.has(.scrollModeWrite) {
                Picker("滚轮模式", selection: Binding(get: { model.scrollMode }, set: { value in
                    model.scrollMode = value
                    Task { await model.applyScrollMode() }
                })) {
                    ForEach(ScrollMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            } else if model.device.has(.scrollModeWrite) {
                // The catalog declares the mode, but this firmware refused the command (0x05).
                Label("这款鼠标的段落 / 无极切换不接受软件命令，请用滚轮后方的模式键切换。", systemImage: "hand.point.up.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.has(.scrollAccelerationWrite) {
                Toggle("滚轮加速", isOn: Binding(get: { model.scrollAcceleration }, set: { value in
                    model.scrollAcceleration = value
                    Task { await model.applyScrollAcceleration() }
                }))
            }
            if model.has(.smartReelWrite) {
                Toggle("智能滚轮（快速滑动时自动切换无极）", isOn: Binding(get: { model.smartReel }, set: { value in
                    model.smartReel = value
                    Task { await model.applySmartReel() }
                }))
            }
        }
        .disabled(model.busy)
    }

    private var keyswitchCard: some View {
        Card(title: "按键优化", symbol: "keyboard") {
            if model.has(.keyswitchOptimizationWrite) {
                Picker("模式", selection: Binding(get: { model.keyswitch }, set: { value in
                    model.keyswitch = value
                    Task { await model.applyKeyswitch() }
                })) {
                    ForEach(KeyswitchOptimization.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .disabled(model.busy)
            } else {
                InfoRow(label: "当前", value: model.state.keyswitch?.displayName ?? "—")
            }
        }
    }

    private var hyperPollingCard: some View {
        Card(title: "HyperPolling 接收器", symbol: "antenna.radiowaves.left.and.right") {
            Picker("指示灯模式", selection: $model.hyperPollingMode) {
                Text("模式 1").tag(1)
                Text("模式 2").tag(2)
                Text("模式 3").tag(3)
            }
            .pickerStyle(.segmented)
            ApplyButton(busy: model.busy) { await model.applyHyperPolling() }
        }
    }
}

private struct DpiField: View {
    let title: String
    @Binding var value: Double
    let maximum: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField("", value: Binding(get: { Int(value) }, set: { value = Double(min(max($0, 100), Int(maximum))) }),
                          format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $value, in: 100...maximum, step: 50).labelsHidden()
            }
            Slider(value: $value.stepped(50), in: 100...maximum)
        }
    }
}

/// Effect picker plus the colour, speed and direction controls the chosen effect takes.
struct LightingEditor: View {
    @Binding var settings: LightingSettings
    let effects: [LightingEffect]

    var body: some View {
        Picker("效果", selection: $settings.effect) {
            ForEach(effects) { Text($0.displayName).tag($0) }
        }
        let colorCount = settings.effect == .custom ? 0 : settings.effect.colorCount
        if colorCount >= 1 {
            RazerColorPicker(title: colorCount > 1 ? "颜色 1" : "颜色", color: $settings.primary)
        }
        if colorCount >= 2 {
            RazerColorPicker(title: "颜色 2", color: $settings.secondary)
        }
        if colorCount >= 3 {
            RazerColorPicker(title: "颜色 3", color: $settings.tertiary)
        }
        if settings.effect.usesSpeed {
            let upper = settings.effect == .reactive ? 4.0 : 3.0
            LabeledSlider(title: "速度", value: Binding(get: { Double(settings.speed) }, set: { settings.speed = UInt8($0) }),
                          range: 1...upper) { ["", "快", "中", "慢", "很慢"][Int($0)] }
        }
        if settings.effect.usesDirection {
            Picker("方向", selection: $settings.direction) {
                Text("向左").tag(UInt8(1))
                Text("向右").tag(UInt8(2))
            }
            .pickerStyle(.segmented)
        }
        if settings.effect == .custom {
            Text("自定义帧会显示最近写入的逐键颜色。").font(.caption).foregroundStyle(.secondary)
        }
    }
}
