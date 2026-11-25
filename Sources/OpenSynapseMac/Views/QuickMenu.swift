import RazerCore
import SwiftUI

/// One device in the menu bar menu, with a submenu of its quick adjustments. Native menus have no
/// sliders, so continuous settings are offered as a few fixed steps. Each control appears under
/// the same condition as on the device page; everything else stays on the page.
struct DeviceQuickMenu: View {
    let item: DeviceItem
    let open: () -> Void

    var body: some View {
        Menu {
            controls
            Divider()
            Button(L("打开设备页面", "Open Device Page"), action: open)
        } label: {
            if let battery = item.page.batteryPercent {
                Label("\(item.page.title)  \(battery)%", systemImage: item.page.symbol)
            } else {
                Label(item.page.title, systemImage: item.page.symbol)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch item.page {
        case .openRazer(let model): OpenRazerQuickItems(model: model)
        case .keyboard(let model): KeyboardQuickItems(model: model)
        case .audio(let model): AudioQuickItems(model: model)
        case .chroma(let model): ChromaQuickItems(model: model)
        case .kraken(let model): KrakenQuickItems(model: model)
        case .blackShark(let model): BlackSharkQuickItems(model: model)
        case .lampArray(let model): LampArrayQuickItems(model: model)
        case .unavailable: EmptyView()
        }
    }
}

/// A submenu with a check mark on the current value. The current value may be none of the
/// options, such as a DPI set on the device page; then nothing is checked.
private struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    let current: Value?
    let options: [(name: String, value: Value)]
    let apply: (Value) -> Void

    var body: some View {
        Menu(title) {
            ForEach(options, id: \.value) { option in
                Toggle(option.name, isOn: Binding(get: { option.value == current }, set: { _ in
                    if option.value != current { apply(option.value) }
                }))
            }
        }
    }
}

private struct ProblemLine: View {
    let error: String?

    var body: some View {
        if let line = error?.split(separator: "\n").first {
            Text("⚠︎ \(String(line))")
        }
    }
}

private func batteryLine(_ percent: Int?, charging: Bool?) -> String? {
    guard let percent else { return nil }
    return L("电量 \(percent)%", "Battery \(percent)%") + (charging == true ? L("（充电中）", " (charging)") : "")
}

private let percentSteps = [0, 25, 50, 75, 100]

// MARK: Mice and other catalog devices

private struct OpenRazerQuickItems: View {
    let model: OpenRazerModel

    var body: some View {
        ProblemLine(error: model.error)
        if let line = batteryLine(model.state.batteryPercent, charging: model.state.charging) {
            Text(line)
        }
        Group {
            dpi
            if model.has(.pollingRateWrite) {
                ChoiceMenu(title: L("回报率：\(model.pollingRate) Hz", "Polling rate: \(model.pollingRate) Hz"), current: model.pollingRate,
                           options: model.device.pollingRateOptions.map { ("\($0) Hz", $0) }) { value in
                    Task { await model.applyPollingRate(value) }
                }
            }
            ForEach(model.brightnessZones, id: \.zone) { caps in
                let percent = model.brightnessPercent(caps.zone)
                ChoiceMenu(title: L("\(caps.zone.displayName)亮度：\(percent)%", "\(caps.zone.displayName) brightness: \(percent)%"), current: percent,
                           options: percentSteps.map { ($0 == 0 ? L("关闭", "Off") : "\($0)%", $0) }) { value in
                    Task { await model.applyBrightness(percent: value, zone: caps.zone) }
                }
            }
            if !model.quickEffects.isEmpty {
                Menu(L("灯效", "Lighting effect")) {
                    ForEach(model.quickEffects) { effect in
                        Button(effect.displayName) { Task { await model.applyEffectToAllZones(effect) } }
                    }
                }
            }
            if model.has(.scrollModeWrite) {
                ChoiceMenu(title: L("滚轮模式：\(model.scrollMode.displayName)", "Scroll mode: \(model.scrollMode.displayName)"), current: model.scrollMode,
                           options: ScrollMode.allCases.map { ($0.displayName, $0) }) { value in
                    model.scrollMode = value
                    Task { await model.applyScrollMode() }
                }
            }
            if model.has(.scrollAccelerationWrite) {
                Toggle(L("滚轮加速", "Scroll acceleration"), isOn: Binding(get: { model.scrollAcceleration }, set: { value in
                    model.scrollAcceleration = value
                    Task { await model.applyScrollAcceleration() }
                }))
            }
            if model.has(.smartReelWrite) {
                Toggle(L("智能滚轮", "Smart Reel"), isOn: Binding(get: { model.smartReel }, set: { value in
                    model.smartReel = value
                    Task { await model.applySmartReel() }
                }))
            }
        }
        .disabled(model.busy)
    }

    @ViewBuilder private var dpi: some View {
        let current = model.state.dpi
        let title = current.map { $0.x == $0.y ? L("DPI：\($0.x)", "DPI: \($0.x)") : L("DPI：\($0.x) × \($0.y)", "DPI: \($0.x) × \($0.y)") } ?? "DPI"
        if model.has(.dpiStagesWrite), let stages = model.state.dpiStages?.stages, !stages.isEmpty {
            ChoiceMenu(title: title, current: stages.first { $0.x == current?.x && $0.y == current?.y }?.number,
                       options: stages.map { ($0.x == $0.y ? "\($0.x)" : "\($0.x) × \($0.y)", $0.number) }) { number in
                if let stage = stages.first(where: { $0.number == number }) {
                    Task { await model.selectStage(stage) }
                }
            }
        } else if model.has(.dpiWrite) {
            let steps = [400, 800, 1600, 3200, 6400].filter { $0 <= model.device.maximumDpi }
            ChoiceMenu(title: title, current: current?.x == current?.y ? current?.x : nil,
                       options: steps.map { ("\($0)", $0) }) { value in
                model.dpiX = Double(value)
                model.dpiY = Double(value)
                model.dpiLinked = true
                Task { await model.applyDpi() }
            }
        }
    }
}

// MARK: Keyboards and Chroma accessories

private struct KeyboardQuickItems: View {
    let model: KeyboardModel

    var body: some View {
        ProblemLine(error: model.error)
        if let line = batteryLine(model.state.batteryPercent, charging: nil) {
            Text(line)
        }
        Group {
            if model.state.pollingRate != nil {
                ChoiceMenu(title: L("回报率：\(model.pollingRate) Hz", "Polling rate: \(model.pollingRate) Hz"), current: model.pollingRate,
                           options: Keyboard25Device.pollingRateOptions.map { ("\($0) Hz", $0) }) { value in
                    Task { await model.applyPollingRate(value) }
                }
            }
            if model.state.gameMode != nil {
                Toggle(L("游戏模式", "Game mode"), isOn: Binding(get: { model.gameMode }, set: { value in
                    model.gameMode = value
                    Task { await model.applyGameMode() }
                }))
            }
        }
        .disabled(model.busy)
        ChromaQuickItems(model: model.lighting)
    }
}

private struct ChromaQuickItems: View {
    let model: ChromaModel

    var body: some View {
        ProblemLine(error: model.identity ? model.error : nil)
        Group {
            ChoiceMenu(title: L("灯效：\(model.effect.displayName)", "Effect: \(model.effect.displayName)"), current: model.effect,
                       options: model.device.supportedEffects.map { ($0.displayName, $0) }) { value in
                model.effect = value
                Task { await model.applyEffect() }
            }
            if model.state.brightnessPercent != nil {
                let percent = Int(model.brightness.rounded())
                ChoiceMenu(title: L("亮度：\(percent)%", "Brightness: \(percent)%"), current: percent,
                           options: percentSteps.map { ($0 == 0 ? L("关闭", "Off") : "\($0)%", $0) }) { value in
                    model.brightness = Double(value)
                    Task { await model.applyBrightness() }
                }
            }
        }
        .disabled(model.busy)
    }
}

// MARK: Headsets

private struct AudioQuickItems: View {
    let model: AudioModel

    var body: some View {
        ProblemLine(error: model.error)
        if let line = batteryLine(model.state.batteryPercent, charging: nil) {
            Text(line)
        }
        Group {
            if model.state.micMuted != nil {
                Toggle(L("麦克风静音", "Microphone mute"), isOn: Binding(get: { model.micMuted }, set: { value in
                    model.micMuted = value
                    Task { await model.applyMicMute() }
                }))
            }
            if model.state.noiseSuppression != nil {
                Toggle(L("麦克风降噪", "Mic noise suppression"), isOn: Binding(get: { model.noiseSuppression }, set: { value in
                    model.noiseSuppression = value
                    Task { await model.applyNoiseSuppression() }
                }))
            }
            if model.state.ancState != nil {
                ChoiceMenu(title: L("主动降噪：\(model.ancState.displayName)", "Active noise cancelling: \(model.ancState.displayName)"), current: model.ancState,
                           options: AncState.allCases.map { ($0.displayName, $0) }) { value in
                    model.ancState = value
                    Task { await model.applyAnc() }
                }
            }
            if model.state.audioSource != nil {
                ChoiceMenu(title: L("音源：\(model.source.displayName)", "Audio source: \(model.source.displayName)"), current: model.source,
                           options: AudioSource.allCases.filter { $0 != .none }.map { ($0.displayName, $0) }) { value in
                    model.source = value
                    Task { await model.applySource() }
                }
            }
            if model.state.eqPreset != nil {
                ChoiceMenu(title: L("均衡器预设", "EQ preset"), current: model.preset,
                           options: HeadsetAudioDevice.presets.map { ($0.name, $0.value) }) { value in
                    model.preset = value
                    Task { await model.applyPreset() }
                }
            }
        }
        .disabled(model.busy)
    }
}

private struct KrakenQuickItems: View {
    let model: KrakenModel

    var body: some View {
        ProblemLine(error: model.error)
        Menu(L("灯效", "Lighting effect")) {
            ForEach(model.device.model.effects.filter { $0 != .custom }) { effect in
                Button(effect.displayName) {
                    model.settings.effect = effect
                    Task { await model.apply() }
                }
            }
        }
        .disabled(model.busy)
    }
}

private struct BlackSharkQuickItems: View {
    let model: BlackSharkModel

    var body: some View {
        ProblemLine(error: model.error)
        if let line = batteryLine(model.state.batteryPercent, charging: model.state.charging) {
            Text(line)
        }
        Group {
            if model.state.sidetone != nil {
                let level = Int(model.sidetone.rounded())
                ChoiceMenu(title: L("侧音：\(level == 0 ? "关闭" : "\(level)")", "Sidetone: \(level == 0 ? "Off" : "\(level)")"), current: level,
                           options: [0, 5, 10, 15].map { ($0 == 0 ? L("关闭", "Off") : "\($0)", $0) }) { value in
                    model.sidetone = Double(value)
                    Task { await model.applySidetone() }
                }
            }
            if model.state.gameChat != nil {
                let balance = Int(model.gameChat.rounded())
                ChoiceMenu(title: L("游戏/聊天：\(Self.balanceName(balance))", "Game/chat: \(Self.balanceName(balance))"), current: balance,
                           options: [0, 5, 10, 15, 20].map { (Self.balanceName($0), $0) }) { value in
                    model.gameChat = Double(value)
                    Task { await model.applyGameChat() }
                }
            }
            if let mode = model.state.ancMode {
                if model.device.supportsAncWrite {
                    ChoiceMenu(title: L("降噪：\(model.ancMode.displayName)", "Noise cancelling: \(model.ancMode.displayName)"), current: model.ancMode,
                               options: BlackSharkAncMode.allCases.map { ($0.displayName, $0) }) { value in
                        model.ancMode = value
                        Task { await model.applyAnc() }
                    }
                } else {
                    Text(L("降噪：\(mode.displayName)", "Noise cancelling: \(mode.displayName)"))
                }
            }
            if model.device.supportsThx, model.state.thx != nil {
                Toggle(L("THX 空间音效", "THX Spatial Audio"), isOn: Binding(get: { model.thx }, set: { value in
                    model.thx = value
                    Task { await model.applyThx() }
                }))
            }
        }
        .disabled(model.busy)
        if let lighting = model.lighting {
            LampArrayQuickItems(model: lighting)
        }
    }

    private static func balanceName(_ value: Int) -> String {
        value < 10 ? L("偏游戏 \(10 - value)", "Game +\(10 - value)") : value > 10 ? L("偏聊天 \(value - 10)", "Chat +\(value - 10)") : L("居中", "Centred")
    }
}

private struct LampArrayQuickItems: View {
    let model: LampArrayModel

    var body: some View {
        Menu(L("灯光", "Lights")) {
            Button(L("关灯", "Lights off")) { Task { await model.off() } }
            Button(L("恢复设备自带灯效", "Restore Device Effect")) { Task { await model.restoreDeviceEffect() } }
        }
        .disabled(model.busy)
    }
}
