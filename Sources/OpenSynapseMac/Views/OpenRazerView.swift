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
                    subtitle: L("\(definition.category.displayName) · \(definition.productIdText) · OpenRazer 协议", "\(definition.category.displayName) · \(definition.productIdText) · OpenRazer protocol"),
                    symbol: definition.category.symbolName,
                    battery: model.state.batteryPercent, charging: model.state.charging,
                    busy: model.busy, reload: { await model.load() })
                StatusBanner(status: model.status, error: model.error)
                if !model.loaded {
                    ProgressView(L("正在读取设备…", "Reading device…")).frame(maxWidth: .infinity).padding(40)
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
                        if !model.mappingButtons.isEmpty {
                            ButtonMappingCard(model: model)
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
        Card(title: L("设备信息", "Device info"), symbol: "info.circle") {
            InfoRow(label: L("型号", "Model"), value: definition.displayName)
            InfoRow(label: "USB ID", value: definition.productIdText)
            InfoRow(label: L("固件版本", "Firmware"), value: model.state.firmware ?? "—")
            InfoRow(label: L("序列号", "Serial number"), value: model.state.serial ?? "—")
            InfoRow(label: L("通信方式", "Connection"), value: model.device.endpoint.pathDescription)
            InfoRow(label: L("HID 接口", "HID interfaces"), value: model.device.endpoint.interface.usageText)
            if let matrix = definition.matrixDimensions {
                InfoRow(label: L("灯光矩阵", "Lighting matrix"), value: L("\(matrix.rows) 行 × \(matrix.columns) 列", "\(matrix.rows) rows × \(matrix.columns) columns"))
            }
            InfoRow(label: L("可用控制", "Available controls"), value: L("\(model.device.capabilities.count) 项", "\(model.device.capabilities.count)"))
        }
    }

    private var performanceCard: some View {
        Card(title: L("性能", "Performance"), symbol: "speedometer") {
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
            Picker(L("回报率", "Polling rate"), selection: selection) {
                ForEach(model.device.pollingRateOptions, id: \.self) { (rate: Int) in
                    Text(verbatim: "\(rate) Hz").tag(rate)
                }
            }
            .disabled(model.busy)
        } else if model.has(.pollingRateRead) {
            InfoRow(label: L("回报率", "Polling rate"), value: model.state.pollingRate.map { "\($0) Hz" } ?? "—")
        }
    }

    @ViewBuilder private var dpiEditor: some View {
        let maximum = Double(model.device.maximumDpi)
        Toggle(L("X / Y 轴 DPI 相同", "Same DPI for X and Y"), isOn: $model.dpiLinked)
        DpiField(title: model.dpiLinked ? "DPI" : L("X 轴 DPI", "X DPI"), value: $model.dpiX, maximum: maximum)
        if !model.dpiLinked {
            DpiField(title: L("Y 轴 DPI", "Y DPI"), value: $model.dpiY, maximum: maximum)
        }
        ApplyButton(L("应用 DPI", "Apply DPI"), busy: model.busy) { await model.applyDpi() }
    }

    private var stagesCard: some View {
        Card(title: L("DPI 档位", "DPI stages"), symbol: "slider.horizontal.3") {
            if model.stages.isEmpty {
                Text(L("设备没有返回档位表", "The device did not return a stage table")).foregroundStyle(.secondary)
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
                    .help(L("设为当前档位", "Make active stage"))
                    Text(L("档位 \(index + 1)", "Stage \(index + 1)")).frame(width: 52, alignment: .leading)
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
                    Button(L("添加档位", "Add Stage"), systemImage: "plus") { model.addStage() }
                        .disabled(model.stages.count >= 5)
                    Spacer()
                    Text("100 – \(model.device.maximumDpi)").font(.caption).foregroundStyle(.secondary)
                }
                ApplyButton(L("写入档位", "Write Stages"), busy: model.busy) { await model.applyStages() }
            }
        }
    }

    private var powerCard: some View {
        Card(title: L("电源", "Power"), symbol: "battery.75percent") {
            if model.has(.batteryRead) {
                InfoRow(label: L("电量", "Battery"), value: model.state.batteryPercent.map { "\($0)%" } ?? "—")
                if model.has(.chargingRead) {
                    InfoRow(label: L("充电", "Charging"), value: model.state.charging.map { $0 ? L("正在充电", "Charging") : L("未充电", "Not charging") } ?? "—")
                }
            }
            if model.has(.idleTimeoutWrite) {
                Divider()
                LabeledSlider(title: L("无操作后休眠", "Sleep after inactivity"), value: $model.idleMinutes, range: 1...15, step: 0.5) {
                    String(format: L("%.1f 分钟", "%.1f min"), $0)
                }
                ApplyButton(busy: model.busy) { await model.applyIdle() }
            }
            if model.has(.lowBatteryThresholdWrite) {
                Divider()
                if let current = model.state.lowBatteryThreshold, ![5, 10, 15, 20, 25].contains(current) {
                    InfoRow(label: L("设备当前低电量提醒", "Device's current low-battery warning"), value: "\(current)%")
                }
                Picker(L("低电量提醒", "Low-battery warning"), selection: $model.lowBattery) {
                    ForEach([5, 10, 15, 20, 25], id: \.self) { Text("\($0)%").tag($0) }
                }
                ApplyButton(busy: model.busy) { await model.applyLowBattery() }
            }
        }
    }

    private var lightingCard: some View {
        Card(title: L("灯效", "Lighting effect"), symbol: "sparkles") {
            let zones = model.effectZones
            if zones.count > 1 {
                Picker(L("灯区", "Zone"), selection: $model.lightingZone) {
                    ForEach(zones, id: \.zone) { Text($0.zone.displayName).tag($0.zone) }
                }
            }
            if let caps = model.device.lightingZones[model.lightingZone], model.lighting[model.lightingZone] != nil {
                let binding = Binding(get: { model.lighting[model.lightingZone]! }, set: { model.lighting[model.lightingZone] = $0 })
                LightingEditor(settings: binding, effects: caps.orderedEffects)
                ApplyButton(L("应用灯效", "Apply Effect"), busy: model.busy) { await model.applyLighting() }
            }
        }
    }

    private var brightnessCard: some View {
        Card(title: L("亮度", "Brightness"), symbol: "sun.max") {
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
            Text(L("松开滑块即写入设备", "Written to the device when you release the slider")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var matrixCard: some View {
        Card(title: L("逐键灯光", "Per-key lighting"), symbol: "keyboard.badge.ellipsis") {
            Text(L("把整块灯光矩阵设为同一颜色（写入自定义帧）。", "Set the whole lighting matrix to one colour (written as a custom frame).")).font(.callout).foregroundStyle(.secondary)
            RazerColorPicker(title: L("颜色", "Colour"), color: $model.matrixColor)
            ApplyButton(L("填充全部按键", "Fill All Keys"), busy: model.busy) { await model.applyMatrixColor() }
        }
    }

    private var scrollCard: some View {
        Card(title: L("滚轮", "Scroll wheel"), symbol: "computermouse") {
            if model.has(.scrollModeWrite) {
                Picker(L("滚轮模式", "Scroll mode"), selection: Binding(get: { model.scrollMode }, set: { value in
                    model.scrollMode = value
                    Task { await model.applyScrollMode() }
                })) {
                    ForEach(ScrollMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            } else if model.device.has(.scrollModeWrite) {
                // The catalog declares the mode, but this firmware refused the command (0x05).
                Label(L("这款鼠标的段落 / 无极切换不接受软件命令，请用滚轮后方的模式键切换。", "This mouse does not accept software commands for notched / free-spin mode; use the mode button behind the wheel."), systemImage: "hand.point.up.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.has(.scrollAccelerationWrite) {
                Toggle(L("滚轮加速", "Scroll acceleration"), isOn: Binding(get: { model.scrollAcceleration }, set: { value in
                    model.scrollAcceleration = value
                    Task { await model.applyScrollAcceleration() }
                }))
            }
            if model.has(.smartReelWrite) {
                Toggle(L("智能滚轮（快速滑动时自动切换无极）", "Smart Reel (switches to free-spin on fast scrolls)"), isOn: Binding(get: { model.smartReel }, set: { value in
                    model.smartReel = value
                    Task { await model.applySmartReel() }
                }))
            }
        }
        .disabled(model.busy)
    }

    private var keyswitchCard: some View {
        Card(title: L("按键优化", "Keyswitch optimisation"), symbol: "keyboard") {
            if model.has(.keyswitchOptimizationWrite) {
                Picker(L("模式", "Mode"), selection: Binding(get: { model.keyswitch }, set: { value in
                    model.keyswitch = value
                    Task { await model.applyKeyswitch() }
                })) {
                    ForEach(KeyswitchOptimization.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .disabled(model.busy)
            } else {
                InfoRow(label: L("当前", "Current"), value: model.state.keyswitch?.displayName ?? "—")
            }
        }
    }

    private var hyperPollingCard: some View {
        Card(title: L("HyperPolling 接收器", "HyperPolling receiver"), symbol: "antenna.radiowaves.left.and.right") {
            Picker(L("指示灯模式", "Indicator mode"), selection: $model.hyperPollingMode) {
                Text(L("模式 1", "Mode 1")).tag(1)
                Text(L("模式 2", "Mode 2")).tag(2)
                Text(L("模式 3", "Mode 3")).tag(3)
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
        Picker(L("效果", "Effect"), selection: $settings.effect) {
            ForEach(effects) { Text($0.displayName).tag($0) }
        }
        let colorCount = settings.effect == .custom ? 0 : settings.effect.colorCount
        if colorCount >= 1 {
            RazerColorPicker(title: colorCount > 1 ? L("颜色 1", "Colour 1") : L("颜色", "Colour"), color: $settings.primary)
        }
        if colorCount >= 2 {
            RazerColorPicker(title: L("颜色 2", "Colour 2"), color: $settings.secondary)
        }
        if colorCount >= 3 {
            RazerColorPicker(title: L("颜色 3", "Colour 3"), color: $settings.tertiary)
        }
        if settings.effect.usesSpeed {
            let upper = settings.effect == .reactive ? 4.0 : 3.0
            LabeledSlider(title: L("速度", "Speed"), value: Binding(get: { Double(settings.speed) }, set: { settings.speed = UInt8($0) }),
                          range: 1...upper) { ["", L("快", "Fast"), L("中", "Medium"), L("慢", "Slow"), L("很慢", "Very slow")][Int($0)] }
        }
        if settings.effect.usesDirection {
            Picker(L("方向", "Direction"), selection: $settings.direction) {
                Text(L("向左", "Left")).tag(UInt8(1))
                Text(L("向右", "Right")).tag(UInt8(2))
            }
            .pickerStyle(.segmented)
        }
        if settings.effect == .custom {
            Text(L("自定义帧会显示最近写入的逐键颜色。", "The custom frame shows the per-key colours written last.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
