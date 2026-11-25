import Foundation

/// Onboard button assignment, class 0x02 (commands 0x84 / 0x8C / 0x0C), as the Razer middleware
/// sends it: profile id, button id, layer, function id and up to five data bytes inside an
/// 80-byte payload. Ported from OpenSynapse's OpenRazerMappingProtocol.
///
/// The layer byte in responses is not reliable (the Basilisk V4 Pro echoes the layer of the last
/// write), so assignments are compared on function id and data only.
public struct ButtonAssignment: Equatable, Sendable {
    public var function: UInt8
    public var data: [UInt8]

    public init(function: UInt8, data: [UInt8]) {
        self.function = function
        self.data = data
    }
}

public enum MappingLayer: UInt8, CaseIterable, Sendable, Identifiable {
    case normal = 0x00
    case hyperShift = 0x01

    public var id: UInt8 { rawValue }
    public var displayName: String { self == .normal ? L("普通层", "Normal layer") : L("HyperShift 层", "HyperShift layer") }
}

enum MappingProtocol {
    static let transactionId: UInt8 = 0x1F
    static let profileId: UInt8 = 0x01
    static let dataSize: UInt8 = 80

    static func getButtonList() throws -> RazerRequest {
        RazerRequest(builder: "mapping.getButtonList",
                     report: try RazerReport(transactionId: transactionId, dataSize: dataSize, commandClass: 0x02, commandId: 0x84))
    }

    static func getAssignment(button: UInt8, layer: MappingLayer) throws -> RazerRequest {
        RazerRequest(builder: "mapping.getAssignment",
                     report: try RazerReport(transactionId: transactionId, dataSize: dataSize, commandClass: 0x02, commandId: 0x8C,
                                             arguments: [profileId, button, layer.rawValue]))
    }

    static func setAssignment(button: UInt8, layer: MappingLayer, _ assignment: ButtonAssignment) throws -> RazerRequest {
        guard assignment.data.count <= 5 else { throw RazerError.invalidArgument(L("按键功能数据最多 5 字节", "Button function data is at most 5 bytes")) }
        let arguments = [profileId, button, layer.rawValue, assignment.function, UInt8(assignment.data.count)] + assignment.data
        return RazerRequest(builder: "mapping.setAssignment",
                            report: try RazerReport(transactionId: transactionId, dataSize: dataSize, commandClass: 0x02, commandId: 0x0C,
                                                    arguments: arguments))
    }

    static func parseButtonList(_ response: RazerReport) throws -> [UInt8] {
        let args = Array(try response.successfulArguments(minimumLength: 1))
        let count = min(Int(args[0]), args.count - 1)
        return Array(args[1..<(1 + count)])
    }

    static func parseAssignment(_ response: RazerReport) throws -> ButtonAssignment {
        let args = Array(try response.successfulArguments(minimumLength: 5))
        let size = min(Int(args[4]), 5)
        return ButtonAssignment(function: args[3], data: Array(args[5..<(5 + size)]))
    }
}

/// Function ids of the button-assignment frame (middleware fnId values).
public enum MappingFunction {
    public static let off: UInt8 = 0x00
    public static let mouseButton: UInt8 = 0x01
    public static let keyboardKey: UInt8 = 0x02
    public static let macroI: UInt8 = 0x03
    public static let macroII: UInt8 = 0x04
    public static let macroIII: UInt8 = 0x05
    public static let dpi: UInt8 = 0x06
    public static let profile: UInt8 = 0x07
    public static let lighting: UInt8 = 0x08
    public static let powerKey: UInt8 = 0x09
    public static let mediaKey: UInt8 = 0x0A
    public static let doubleClick: UInt8 = 0x0B
    public static let modeButton: UInt8 = 0x0C
    public static let turboKey: UInt8 = 0x0D
    public static let turboButton: UInt8 = 0x0E
    public static let macroIV: UInt8 = 0x0F
    public static let controller: UInt8 = 0x10
    public static let razerKey: UInt8 = 0x11
    public static let scrollWheelMode: UInt8 = 0x12
    public static let windowsShortcut: UInt8 = 0x15
}

public enum MappingGroup: String, CaseIterable, Sendable, Identifiable {
    case off, mouseButton, turboMouseButton, keyboardKey, dpi, profile, mediaKey, powerKey, doubleClick, scrollWheelMode, hyperShift

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: L("禁用", "Disabled")
        case .mouseButton: L("鼠标按键", "Mouse button")
        case .turboMouseButton: L("鼠标按键（按住连发）", "Mouse button (hold to repeat)")
        case .keyboardKey: L("键盘按键", "Keyboard key")
        case .dpi: "DPI"
        case .profile: L("配置文件", "Profile")
        case .mediaKey: L("媒体键", "Media key")
        case .powerKey: L("电源键", "Power key")
        case .doubleClick: L("双击", "Double click")
        case .scrollWheelMode: L("滚轮模式（无极 / 段落）", "Scroll mode (free-spin / notched)")
        case .hyperShift: "HyperShift"
        }
    }
}

public struct MappingOption: Identifiable, Hashable, Sendable {
    public let name: String
    public let code: UInt16
    public var id: UInt16 { code }
}

/// Selectable onboard mappings, transcribed from OpenSynapse's OpenRazerMappingActions (which
/// follows the middleware's fnId switch). Groups that need data the app cannot read from the
/// device (macro slots, controller buttons) are not offered. Turbo mouse buttons use the rate the
/// Basilisk wheel tilt ships with. Windows-only actions
/// (Game Bar and similar shortcuts) are left out on macOS.
public enum MappingActions {
    public static var modifiers: [(name: String, mask: UInt8)] { [
        (L("无", "None"), 0x00), ("Control", 0x01), ("Shift", 0x02), ("Option (Alt)", 0x04), ("Command (Win)", 0x08),
    ] }

    static var mouseButtons: [(String, UInt8)] { [
        (L("左键", "Left button"), 0x01), (L("右键", "Right button"), 0x02), (L("中键", "Middle button"), 0x03), (L("后退", "Back"), 0x04), (L("前进", "Forward"), 0x05),
        (L("按键 6", "Button 6"), 0x06), (L("按键 7", "Button 7"), 0x07), (L("按键 8", "Button 8"), 0x08), (L("滚轮上滚", "Scroll up"), 0x09), (L("滚轮下滚", "Scroll down"), 0x0A),
        (L("DPI 升", "DPI up"), 0x0B), (L("DPI 降", "DPI down"), 0x0C), (L("用户选择", "User select"), 0x0D), (L("配置切换", "Profile switch"), 0x0E), (L("灵敏度离合", "Sensitivity clutch"), 0x0F),
        (L("DPI 循环（升）", "DPI cycle (up)"), 0x60), (L("DPI 循环（降）", "DPI cycle (down)"), 0x61), (L("上一页", "Page up"), 0x63), (L("下一页", "Page down"), 0x64),
        (L("音量加", "Volume up"), 0x65), (L("音量减", "Volume down"), 0x66), (L("静音", "Mute"), 0x67), (L("向左滚动", "Scroll left"), 0x68), (L("向右滚动", "Scroll right"), 0x69),
        (L("切换滚轮模式", "Toggle scroll mode"), 0x6A),
    ] }

    // USB HID usage page 0x07. Modifier keys are stored as [usage, 0].
    static var keys: [(String, UInt8)] {
        var keys: [(String, UInt8)] = []
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { keys.append((String(letter), UInt8(4 + index))) }
        for (index, digit) in "1234567890".enumerated() { keys.append((String(digit), UInt8(30 + index))) }
        keys += [
            ("Return", 40), ("Esc", 41), (L("Delete（退格）", "Delete (Backspace)"), 42), ("Tab", 43), (L("空格", "Space"), 44),
            ("-", 45), ("=", 46), ("[", 47), ("]", 48), ("\\", 49), (";", 51), ("'", 52), ("`", 53),
            (",", 54), (".", 55), ("/", 56), ("Caps Lock", 57),
        ]
        for number in 1...12 { keys.append(("F\(number)", UInt8(57 + number))) }
        // F13–F20 exist on no Mac keyboard, so they make conflict-free trigger keys.
        for number in 13...20 {
            keys.append(("F\(number)", UInt8(91 + number)))
        }
        keys += [
            ("Print Screen", 70), ("Scroll Lock", 71), ("Pause", 72), ("Insert", 73), ("Home", 74),
            ("Page Up", 75), ("Forward Delete", 76), ("End", 77), ("Page Down", 78),
            ("→", 79), ("←", 80), ("↓", 81), ("↑", 82),
            (L("左 Control", "Left Control"), 224), (L("左 Shift", "Left Shift"), 225), (L("左 Option", "Left Option"), 226), (L("左 Command", "Left Command"), 227),
            (L("右 Control", "Right Control"), 228), (L("右 Shift", "Right Shift"), 229), (L("右 Option", "Right Option"), 230), (L("右 Command", "Right Command"), 231),
        ]
        return keys
    }

    static var dpiActions: [(String, UInt8)] { [(L("DPI 升", "DPI up"), 0x01), (L("DPI 降", "DPI down"), 0x02), (L("DPI 循环（升）", "DPI cycle (up)"), 0x06), (L("DPI 循环（降）", "DPI cycle (down)"), 0x07)] }
    static var profileActions: [(String, UInt8)] { [(L("下一个配置", "Next profile"), 0x01), (L("上一个配置", "Previous profile"), 0x02), (L("配置循环（升）", "Profile cycle (up)"), 0x04), (L("配置循环（降）", "Profile cycle (down)"), 0x05)] }
    static var mediaKeys: [(String, UInt16)] { [
        (L("静音", "Mute"), 226), (L("音量加", "Volume up"), 233), (L("音量减", "Volume down"), 234), (L("播放 / 暂停", "Play / Pause"), 205), (L("下一首", "Next track"), 181), (L("上一首", "Previous track"), 182),
        (L("停止", "Stop"), 183), (L("推出", "Eject"), 184), (L("亮度加", "Brightness up"), 111), (L("亮度减", "Brightness down"), 112),
    ] }
    static var powerKeys: [(String, UInt8)] { [(L("电源", "Power"), 129), (L("睡眠", "Sleep"), 130), (L("唤醒", "Wake"), 131)] }
    // Upstream also lists codes 0x02–0x05 as "scroll up / down / cycle", but on the Basilisk V3
    // they produce no scrolling at all, so only the mode toggle is offered.
    static var scrollModes: [(String, UInt8)] { [(L("切换滚轮模式", "Toggle scroll mode"), 0x01)] }
    /// The repeat rate of the Basilisk's factory wheel-tilt mapping (turbo scroll left / right).
    static let turboRate: [UInt8] = [0x00, 0x14]

    public static func options(_ group: MappingGroup) -> [MappingOption] {
        func list<T: BinaryInteger>(_ entries: [(String, T)]) -> [MappingOption] {
            entries.map { MappingOption(name: $0.0, code: UInt16($0.1)) }
        }
        switch group {
        case .off: return [MappingOption(name: L("禁用", "Disabled"), code: 0)]
        case .mouseButton: return list(mouseButtons)
        case .turboMouseButton: return list(mouseButtons)
        case .keyboardKey: return list(keys)
        case .dpi: return list(dpiActions)
        case .profile: return list(profileActions)
        case .mediaKey: return list(mediaKeys)
        case .powerKey: return list(powerKeys)
        case .doubleClick: return [MappingOption(name: L("双击左键", "Double left click"), code: 1)]
        case .scrollWheelMode: return list(scrollModes)
        case .hyperShift: return [MappingOption(name: L("按住切换到 HyperShift 层", "Hold for HyperShift layer"), code: 1)]
        }
    }

    public static func assignment(_ group: MappingGroup, _ option: MappingOption, modifier: UInt8 = 0) -> ButtonAssignment {
        let code = option.code
        switch group {
        case .off: return ButtonAssignment(function: MappingFunction.off, data: [])
        case .mouseButton: return ButtonAssignment(function: MappingFunction.mouseButton, data: [UInt8(code)])
        case .turboMouseButton: return ButtonAssignment(function: MappingFunction.turboButton, data: [UInt8(code)] + turboRate)
        case .keyboardKey:
            return code >= 224
                ? ButtonAssignment(function: MappingFunction.keyboardKey, data: [UInt8(code), 0x00])
                : ButtonAssignment(function: MappingFunction.keyboardKey, data: [modifier, UInt8(code)])
        case .dpi: return ButtonAssignment(function: MappingFunction.dpi, data: [UInt8(code)])
        case .profile: return ButtonAssignment(function: MappingFunction.profile, data: [UInt8(code)])
        case .mediaKey: return ButtonAssignment(function: MappingFunction.mediaKey, data: [UInt8(code >> 8), UInt8(code & 0xFF)])
        case .powerKey: return ButtonAssignment(function: MappingFunction.powerKey, data: [UInt8(code)])
        case .doubleClick: return ButtonAssignment(function: MappingFunction.doubleClick, data: [0x01])
        case .scrollWheelMode: return ButtonAssignment(function: MappingFunction.scrollWheelMode, data: [UInt8(code)])
        case .hyperShift: return ButtonAssignment(function: MappingFunction.modeButton, data: [0x01])
        }
    }

    /// Group and option that reproduce an existing assignment, for pre-selecting the editor.
    public static func selection(for assignment: ButtonAssignment) -> (group: MappingGroup, option: MappingOption, modifier: UInt8)? {
        for group in MappingGroup.allCases {
            for option in options(group) {
                if self.assignment(group, option) == assignment { return (group, option, 0) }
                // Some firmware reports a turbo mapping with a shorter length, so match the button only.
                if group == .turboMouseButton, assignment.function == MappingFunction.turboButton,
                   assignment.data.first == UInt8(option.code) {
                    return (group, option, 0)
                }
                if group == .keyboardKey, assignment.function == MappingFunction.keyboardKey, assignment.data.count == 2,
                   option.code < 224, assignment.data[1] == UInt8(option.code) {
                    return (group, option, assignment.data[0])
                }
            }
        }
        return nil
    }

    public static func describe(_ assignment: ButtonAssignment) -> String {
        let data = assignment.data
        func name<T: BinaryInteger>(_ entries: [(String, T)], _ value: T, _ fallback: String) -> String {
            entries.first { $0.1 == value }?.0 ?? fallback
        }
        switch assignment.function {
        case MappingFunction.off: return L("禁用", "Disabled")
        case MappingFunction.mouseButton where !data.isEmpty:
            return name(mouseButtons, data[0], String(format: L("鼠标按键 0x%02X", "Mouse button 0x%02X"), data[0]))
        case MappingFunction.keyboardKey where data.count >= 2:
            if data[1] == 0, data[0] >= 224 { return L("键盘 ", "Keyboard ") + name(keys, data[0], L("按键 \(data[0])", "Key \(data[0])")) }
            let key = name(keys, data[1], L("按键 \(data[1])", "Key \(data[1])"))
            let modifier = modifiers.first { $0.mask == data[0] && $0.mask != 0 }?.name
            return L("键盘 ", "Keyboard ") + (modifier.map { "\($0) + \(key)" } ?? key)
        case MappingFunction.dpi where !data.isEmpty: return name(dpiActions, data[0], "DPI \(data[0])")
        case MappingFunction.profile where !data.isEmpty: return name(profileActions, data[0], L("配置 \(data[0])", "Profile \(data[0])"))
        case MappingFunction.mediaKey where data.count >= 2:
            return L("媒体键 ", "Media key ") + name(mediaKeys, UInt16(data[0]) << 8 | UInt16(data[1]), String(format: "0x%02X%02X", data[0], data[1]))
        case MappingFunction.powerKey where !data.isEmpty: return name(powerKeys, data[0], L("电源键 \(data[0])", "Power key \(data[0])"))
        case MappingFunction.doubleClick: return L("双击", "Double click")
        case MappingFunction.scrollWheelMode where !data.isEmpty: return name(scrollModes, data[0], String(format: L("滚轮模式指令 0x%02X（不滚动）", "Scroll mode command 0x%02X (does not scroll)"), data[0]))
        // Data 0x01 is HyperShift. The Basilisk V4 Pro's clutch button ships with data 0x39,
        // whose meaning is not documented, so it is shown as is.
        case MappingFunction.modeButton where data == [0x01]: return "HyperShift"
        case MappingFunction.modeButton:
            return L("模式键功能", "Mode button function") + (data.isEmpty ? "" : " 0x\(data.hexString)") + L("（出厂设置）", " (factory setting)")
        case MappingFunction.turboButton, MappingFunction.turboKey:
            return (data.first.map { name(mouseButtons, $0, String(format: L("鼠标按键 0x%02X", "Mouse button 0x%02X"), $0)) } ?? "") + L("（按住连发）", " (hold to repeat)")
        case MappingFunction.macroI, MappingFunction.macroII, MappingFunction.macroIII, MappingFunction.macroIV: return L("宏", "Macro")
        default:
            return String(format: L("功能 0x%02X", "Function 0x%02X"), assignment.function) + (data.isEmpty ? "" : " [\(data.hexString)]")
        }
    }

    /// Button names. A button's id is the mouse-button code of the function it ships with, so the
    /// generic names describe that function, not where the button sits. Where a button lives
    /// differs per model, so placement is only named for models checked against the hardware.
    public static func buttonName(_ id: UInt8, productId: UInt16? = nil) -> String {
        if let productId, let name = modelButtonNames[productId]?[id] { return name }
        switch id {
        case 0x01: return L("左键", "Left button")
        case 0x02: return L("右键", "Right button")
        case 0x03: return L("滚轮按下（中键）", "Wheel click (middle)")
        case 0x04: return L("侧键（后退）", "Side button (back)")
        case 0x05: return L("侧键（前进）", "Side button (forward)")
        case 0x09: return L("滚轮上滚", "Scroll up")
        case 0x0A: return L("滚轮下滚", "Scroll down")
        case 0x0B: return L("DPI 升键", "DPI up button")
        case 0x0C: return L("DPI 降键", "DPI down button")
        case 0x0E: return L("配置切换键", "Profile button")
        case 0x0F: return L("灵敏度离合键", "Sensitivity clutch button")
        case 0x34: return L("滚轮左倾", "Wheel tilt left")
        case 0x35: return L("滚轮右倾", "Wheel tilt right")
        case 0x60: return L("DPI 键", "DPI button")
        case 0x6A: return L("滚轮模式键", "Scroll mode button")
        default: return String(format: L("按键 0x%02X", "Button 0x%02X"), id)
        }
    }

    /// Per-model names, by USB product id.
    /// - Basilisk V4 Pro: 0x0E and 0x80 were identified by pressing them; 0x39 is the paddle
    ///   (the model has no 0x0F, and 0x39 ships with the clutch function).
    /// - Basilisk V3: 0x0E is the profile button on the underside, 0x0F the multi-function paddle.
    static var modelButtonNames: [UInt16: [UInt8: String]] {
        let basiliskV4Pro: [UInt8: String] = [
            0x0E: L("M1 边缘键（左键旁）", "M1 edge button (beside left click)"), 0x39: L("多功能扳机键", "Multi-function paddle"), 0x80: L("第三侧键（最前）", "Third side button (front)"),
        ]
        let basiliskV3: [UInt8: String] = [0x0E: L("配置切换键（底部）", "Profile button (underside)"), 0x0F: L("多功能扳机键", "Multi-function paddle")]
        return [0x00E2: basiliskV4Pro, 0x00E3: basiliskV4Pro, 0x0099: basiliskV3]
    }
}
