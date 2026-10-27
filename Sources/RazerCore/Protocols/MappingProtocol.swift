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
    public var displayName: String { self == .normal ? "普通层" : "HyperShift 层" }
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
        guard assignment.data.count <= 5 else { throw RazerError.invalidArgument("按键功能数据最多 5 字节") }
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
        case .off: "禁用"
        case .mouseButton: "鼠标按键"
        case .turboMouseButton: "鼠标按键（按住连发）"
        case .keyboardKey: "键盘按键"
        case .dpi: "DPI"
        case .profile: "配置文件"
        case .mediaKey: "媒体键"
        case .powerKey: "电源键"
        case .doubleClick: "双击"
        case .scrollWheelMode: "滚轮模式（无极 / 段落）"
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
    public static let modifiers: [(name: String, mask: UInt8)] = [
        ("无", 0x00), ("Control", 0x01), ("Shift", 0x02), ("Option (Alt)", 0x04), ("Command (Win)", 0x08),
    ]

    static let mouseButtons: [(String, UInt8)] = [
        ("左键", 0x01), ("右键", 0x02), ("中键", 0x03), ("后退", 0x04), ("前进", 0x05),
        ("按键 6", 0x06), ("按键 7", 0x07), ("按键 8", 0x08), ("滚轮上滚", 0x09), ("滚轮下滚", 0x0A),
        ("DPI 升", 0x0B), ("DPI 降", 0x0C), ("用户选择", 0x0D), ("配置切换", 0x0E), ("灵敏度离合", 0x0F),
        ("DPI 循环（升）", 0x60), ("DPI 循环（降）", 0x61), ("上一页", 0x63), ("下一页", 0x64),
        ("音量加", 0x65), ("音量减", 0x66), ("静音", 0x67), ("向左滚动", 0x68), ("向右滚动", 0x69),
        ("切换滚轮模式", 0x6A),
    ]

    // USB HID usage page 0x07. Modifier keys are stored as [usage, 0].
    static let keys: [(String, UInt8)] = {
        var keys: [(String, UInt8)] = []
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { keys.append((String(letter), UInt8(4 + index))) }
        for (index, digit) in "1234567890".enumerated() { keys.append((String(digit), UInt8(30 + index))) }
        keys += [
            ("Return", 40), ("Esc", 41), ("Delete（退格）", 42), ("Tab", 43), ("空格", 44),
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
            ("左 Control", 224), ("左 Shift", 225), ("左 Option", 226), ("左 Command", 227),
            ("右 Control", 228), ("右 Shift", 229), ("右 Option", 230), ("右 Command", 231),
        ]
        return keys
    }()

    static let dpiActions: [(String, UInt8)] = [("DPI 升", 0x01), ("DPI 降", 0x02), ("DPI 循环（升）", 0x06), ("DPI 循环（降）", 0x07)]
    static let profileActions: [(String, UInt8)] = [("下一个配置", 0x01), ("上一个配置", 0x02), ("配置循环（升）", 0x04), ("配置循环（降）", 0x05)]
    static let mediaKeys: [(String, UInt16)] = [
        ("静音", 226), ("音量加", 233), ("音量减", 234), ("播放 / 暂停", 205), ("下一首", 181), ("上一首", 182),
        ("停止", 183), ("推出", 184), ("亮度加", 111), ("亮度减", 112),
    ]
    static let powerKeys: [(String, UInt8)] = [("电源", 129), ("睡眠", 130), ("唤醒", 131)]
    // Upstream also lists codes 0x02–0x05 as "scroll up / down / cycle", but on the Basilisk V3
    // they produce no scrolling at all, so only the mode toggle is offered.
    static let scrollModes: [(String, UInt8)] = [("切换滚轮模式", 0x01)]
    /// The repeat rate of the Basilisk's factory wheel-tilt mapping (turbo scroll left / right).
    static let turboRate: [UInt8] = [0x00, 0x14]

    public static func options(_ group: MappingGroup) -> [MappingOption] {
        func list<T: BinaryInteger>(_ entries: [(String, T)]) -> [MappingOption] {
            entries.map { MappingOption(name: $0.0, code: UInt16($0.1)) }
        }
        switch group {
        case .off: return [MappingOption(name: "禁用", code: 0)]
        case .mouseButton: return list(mouseButtons)
        case .turboMouseButton: return list(mouseButtons)
        case .keyboardKey: return list(keys)
        case .dpi: return list(dpiActions)
        case .profile: return list(profileActions)
        case .mediaKey: return list(mediaKeys)
        case .powerKey: return list(powerKeys)
        case .doubleClick: return [MappingOption(name: "双击左键", code: 1)]
        case .scrollWheelMode: return list(scrollModes)
        case .hyperShift: return [MappingOption(name: "按住切换到 HyperShift 层", code: 1)]
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
        case MappingFunction.off: return "禁用"
        case MappingFunction.mouseButton where !data.isEmpty:
            return name(mouseButtons, data[0], String(format: "鼠标按键 0x%02X", data[0]))
        case MappingFunction.keyboardKey where data.count >= 2:
            if data[1] == 0, data[0] >= 224 { return "键盘 " + name(keys, data[0], "按键 \(data[0])") }
            let key = name(keys, data[1], "按键 \(data[1])")
            let modifier = modifiers.first { $0.mask == data[0] && $0.mask != 0 }?.name
            return "键盘 " + (modifier.map { "\($0) + \(key)" } ?? key)
        case MappingFunction.dpi where !data.isEmpty: return name(dpiActions, data[0], "DPI \(data[0])")
        case MappingFunction.profile where !data.isEmpty: return name(profileActions, data[0], "配置 \(data[0])")
        case MappingFunction.mediaKey where data.count >= 2:
            return "媒体键 " + name(mediaKeys, UInt16(data[0]) << 8 | UInt16(data[1]), String(format: "0x%02X%02X", data[0], data[1]))
        case MappingFunction.powerKey where !data.isEmpty: return name(powerKeys, data[0], "电源键 \(data[0])")
        case MappingFunction.doubleClick: return "双击"
        case MappingFunction.scrollWheelMode where !data.isEmpty: return name(scrollModes, data[0], String(format: "滚轮模式指令 0x%02X（不滚动）", data[0]))
        // Data 0x01 is HyperShift. The Basilisk V4 Pro's clutch button ships with data 0x39,
        // whose meaning is not documented, so it is shown as is.
        case MappingFunction.modeButton where data == [0x01]: return "HyperShift"
        case MappingFunction.modeButton:
            return "模式键功能" + (data.isEmpty ? "" : " 0x\(data.hexString)") + "（出厂设置）"
        case MappingFunction.turboButton, MappingFunction.turboKey:
            return (data.first.map { name(mouseButtons, $0, String(format: "鼠标按键 0x%02X", $0)) } ?? "") + "（按住连发）"
        case MappingFunction.macroI, MappingFunction.macroII, MappingFunction.macroIII, MappingFunction.macroIV: return "宏"
        default:
            return String(format: "功能 0x%02X", assignment.function) + (data.isEmpty ? "" : " [\(data.hexString)]")
        }
    }

    /// Button names. A button's id is the mouse-button code of the function it ships with, so the
    /// generic names describe that function, not where the button sits. Where a button lives
    /// differs per model, so placement is only named for models checked against the hardware.
    public static func buttonName(_ id: UInt8, productId: UInt16? = nil) -> String {
        if let productId, let name = modelButtonNames[productId]?[id] { return name }
        switch id {
        case 0x01: return "左键"
        case 0x02: return "右键"
        case 0x03: return "滚轮按下（中键）"
        case 0x04: return "侧键（后退）"
        case 0x05: return "侧键（前进）"
        case 0x09: return "滚轮上滚"
        case 0x0A: return "滚轮下滚"
        case 0x0B: return "DPI 升键"
        case 0x0C: return "DPI 降键"
        case 0x0E: return "配置切换键"
        case 0x0F: return "灵敏度离合键"
        case 0x34: return "滚轮左倾"
        case 0x35: return "滚轮右倾"
        case 0x60: return "DPI 键"
        case 0x6A: return "滚轮模式键"
        default: return String(format: "按键 0x%02X", id)
        }
    }

    /// Per-model names, by USB product id.
    /// - Basilisk V4 Pro: 0x0E and 0x80 were identified by pressing them; 0x39 is the paddle
    ///   (the model has no 0x0F, and 0x39 ships with the clutch function).
    /// - Basilisk V3: 0x0E is the profile button on the underside, 0x0F the multi-function paddle.
    static let modelButtonNames: [UInt16: [UInt8: String]] = {
        let basiliskV4Pro: [UInt8: String] = [
            0x0E: "M1 边缘键（左键旁）", 0x39: "多功能扳机键", 0x80: "第三侧键（最前）",
        ]
        let basiliskV3: [UInt8: String] = [0x0E: "配置切换键（底部）", 0x0F: "多功能扳机键"]
        return [0x00E2: basiliskV4Pro, 0x00E3: basiliskV4Pro, 0x0099: basiliskV3]
    }()
}
