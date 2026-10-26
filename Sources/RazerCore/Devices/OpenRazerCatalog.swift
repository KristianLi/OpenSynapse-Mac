import Foundation

public let razerVendorId: UInt16 = 0x1532

public enum DeviceCategory: String, Sendable, CaseIterable {
    case mouse, keyboard, laptop, accessory, mouseMat, monitor, headset, speaker, microphone

    public var displayName: String {
        switch self {
        case .mouse: "鼠标"
        case .keyboard: "键盘"
        case .laptop: "笔记本"
        case .accessory: "配件"
        case .mouseMat: "鼠标垫"
        case .monitor: "显示器"
        case .headset: "耳机"
        case .speaker: "音箱"
        case .microphone: "麦克风"
        }
    }

    public var symbolName: String {
        switch self {
        case .mouse: "computermouse"
        case .keyboard: "keyboard"
        case .laptop: "laptopcomputer"
        case .accessory: "lightbulb.led"
        case .mouseMat: "rectangle.on.rectangle"
        case .monitor: "display"
        case .headset: "headphones"
        case .speaker: "hifispeaker"
        case .microphone: "mic"
        }
    }
}

public enum Storage: UInt8, Sendable {
    case temporary = 0x00
    case persistent = 0x01
}

public enum LedZone: UInt8, Sendable, CaseIterable, Comparable, Identifiable {
    case all = 0x00
    case scrollWheel = 0x01
    case battery = 0x03
    case logo = 0x04
    case backlight = 0x05
    case macro = 0x07
    case game = 0x08
    case profileRed = 0x0C
    case profileGreen = 0x0D
    case profileBlue = 0x0E
    case rightSide = 0x10
    case leftSide = 0x11
    case charging = 0x20
    case fastCharging = 0x21
    case fullyCharged = 0x22

    public var id: UInt8 { rawValue }

    public static func < (lhs: LedZone, rhs: LedZone) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .all: "整体"
        case .scrollWheel: "滚轮"
        case .battery: "电池指示"
        case .logo: "标志"
        case .backlight: "背光"
        case .macro: "宏指示灯"
        case .game: "游戏模式灯"
        case .profileRed: "配置灯（红）"
        case .profileGreen: "配置灯（绿）"
        case .profileBlue: "配置灯（蓝）"
        case .rightSide: "右侧灯带"
        case .leftSide: "左侧灯带"
        case .charging: "充电中"
        case .fastCharging: "快充中"
        case .fullyCharged: "已充满"
        }
    }
}

public struct MatrixDimensions: Equatable, Sendable {
    public let rows: UInt8
    public let columns: UInt8
}

public struct CommandStep: Equatable, Sendable {
    public let transactionId: UInt8
    public let fixedArgument0: UInt8
}

/// Device quirks that upstream handles with a dedicated protocol class instead of the catalog.
public enum DeviceQuirk: Sendable {
    /// Viper V3 HyperSpeed (product 184): DPI is written with storage 0x00 and the DPI stage
    /// table declares its real argument length instead of 0x26.
    case viperProduct184
}

public struct DeviceDefinition: Sendable {
    public let productId: UInt16
    public let displayName: String
    public let category: DeviceCategory
    public let sourceCapabilities: Set<String>
    public let maximumDpi: Int?
    public let pollingRates: [Int]
    public let matrixDimensions: MatrixDimensions?
    /// Delay between SET_REPORT and GET_REPORT.
    public let deviceWait: TimeInterval
    public let transactions: [String: UInt8]
    public let builderArgumentPrefixes: [String: [[UInt8]]]
    public let defaultStorage: Storage
    public let defaultLedZone: LedZone
    public let commandSequences: [String: [CommandStep]]
    public let quirk: DeviceQuirk?

    public init(
        productId: UInt16,
        displayName: String,
        category: DeviceCategory,
        sourceCapabilities: Set<String>,
        maximumDpi: Int?,
        pollingRates: [Int],
        matrixDimensions: MatrixDimensions?,
        deviceWait: TimeInterval,
        transactions: [String: UInt8],
        builderArgumentPrefixes: [String: [[UInt8]]],
        defaultStorage: Storage,
        defaultLedZone: LedZone,
        commandSequences: [String: [CommandStep]],
        quirk: DeviceQuirk? = nil
    ) {
        self.productId = productId
        self.displayName = displayName
        self.category = category
        self.sourceCapabilities = sourceCapabilities
        self.maximumDpi = maximumDpi
        self.pollingRates = pollingRates
        self.matrixDimensions = matrixDimensions
        self.deviceWait = deviceWait
        self.transactions = transactions
        self.builderArgumentPrefixes = builderArgumentPrefixes
        self.defaultStorage = defaultStorage
        self.defaultLedZone = defaultLedZone
        self.commandSequences = commandSequences
        self.quirk = quirk
    }

    public var productIdText: String { String(format: "1532:%04X", productId) }

    func has(_ capability: String) -> Bool { sourceCapabilities.contains(capability) }

    func hasBuilder(_ builder: String) -> Bool {
        transactions[builder] != nil || commandSequences[builder] != nil
    }

    func requiredTransaction(_ builder: String) throws -> UInt8 {
        guard let value = transactions[builder] else {
            throw RazerError.notSupported("\(productIdText) 没有 \(builder) 的确定事务号")
        }
        return value
    }

    func requiredFixedArgument(_ builder: String, index: Int) throws -> UInt8 {
        guard let prefixes = builderArgumentPrefixes[builder] else {
            throw RazerError.notSupported("\(productIdText) 没有 \(builder) 的固定参数")
        }
        let values = Set(prefixes.filter { $0.count > index }.map { $0[index] })
        guard values.count == 1, let value = values.first else {
            throw RazerError.notSupported("\(productIdText) 的 \(builder) 参数 \(index) 不唯一")
        }
        return value
    }

    func with(
        productId: UInt16? = nil,
        displayName: String? = nil,
        maximumDpi: Int?? = nil,
        pollingRates: [Int]? = nil,
        transactions: [String: UInt8]? = nil,
        builderArgumentPrefixes: [String: [[UInt8]]]? = nil,
        commandSequences: [String: [CommandStep]]? = nil
    ) -> DeviceDefinition {
        DeviceDefinition(
            productId: productId ?? self.productId,
            displayName: displayName ?? self.displayName,
            category: category,
            sourceCapabilities: sourceCapabilities,
            maximumDpi: maximumDpi ?? self.maximumDpi,
            pollingRates: pollingRates ?? self.pollingRates,
            matrixDimensions: matrixDimensions,
            deviceWait: deviceWait,
            transactions: transactions ?? self.transactions,
            builderArgumentPrefixes: builderArgumentPrefixes ?? self.builderArgumentPrefixes,
            defaultStorage: defaultStorage,
            defaultLedZone: defaultLedZone,
            commandSequences: commandSequences ?? self.commandSequences,
            quirk: quirk)
    }
}

/// The OpenRazer device catalog pinned by OpenSynapse, plus its locally admitted entries.
public final class OpenRazerCatalog: Sendable {
    public static let sourceCommit = "477f4d6d3ab7e9deb6310d5bd3742560c5cbe80d"
    public static let expectedUpstreamCount = 259

    public static let builtIn: OpenRazerCatalog = {
        do {
            return try OpenRazerCatalog.loadBuiltIn()
        } catch {
            fatalError("无法加载内置 OpenRazer 设备目录：\(error)")
        }
    }()

    public let devices: [DeviceDefinition]
    public let upstreamCount: Int
    private let byProductId: [UInt16: DeviceDefinition]

    init(devices: [UInt16: DeviceDefinition], upstreamCount: Int) {
        byProductId = devices
        self.devices = devices.values.sorted { $0.productId < $1.productId }
        self.upstreamCount = upstreamCount
    }

    public func find(productId: UInt16) -> DeviceDefinition? { byProductId[productId] }

    /// Inside the .app the resource bundle lives in Contents/Resources (where code signing
    /// expects it); SwiftPM's own accessor only looks next to the executable or in .build.
    ///
    /// Release builds avoid `Bundle.module`: its generated accessor embeds the absolute build
    /// path (and with it the builder's user name) into the shipped binary.
    private static var resourceBundle: Bundle {
        let name = "OpenSynapseMac_RazerCore.bundle"
        let directories = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
            Bundle(for: OpenRazerCatalog.self).bundleURL.deletingLastPathComponent(),
        ]
        for directory in directories.compactMap({ $0 }) {
            if let bundle = Bundle(url: directory.appendingPathComponent(name)) {
                return bundle
            }
        }
        #if DEBUG
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    static func loadBuiltIn() throws -> OpenRazerCatalog {
        var devices: [UInt16: DeviceDefinition] = [:]
        let bundle = resourceBundle
        for name in ["accessories", "keyboards", "laptops", "mice"] {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Resources")
                ?? bundle.url(forResource: name, withExtension: "json")
            else {
                throw RazerError.invalidArgument("缺少目录资源 \(name).json")
            }
            try addDocument(try Data(contentsOf: url), source: name, into: &devices)
        }
        let upstreamCount = devices.count
        guard upstreamCount == expectedUpstreamCount else {
            throw RazerError.invalidArgument("目录包含 \(upstreamCount) 个设备，预期 \(expectedUpstreamCount)")
        }
        addLocallyAdmittedDevices(&devices)
        return OpenRazerCatalog(devices: devices, upstreamCount: upstreamCount)
    }

    private struct Document: Decodable {
        struct Source: Decodable {
            let repository: String
            let commit: String
        }
        struct Step: Decodable {
            let transactionId: String
            let fixedArgument0: String
        }
        struct Device: Decodable {
            let productId: String
            let displayName: String
            let category: String
            let capabilitySet: String
            let maximumDpi: Int?
            let pollRates: [Int]?
            let matrixDimensions: [Int]?
            let waitMicroseconds: Int
            let transactions: [String: String]
            let builderArgumentPrefixes: [String: [String]]
            let defaultStorage: String?
            let defaultLedZone: String?
            let commandSequences: [String: [Step]]
            let ambiguousTransactions: [String]
        }
        let schemaVersion: Int
        let source: Source
        let capabilitySets: [String: [String]]
        let devices: [Device]
    }

    private static func addDocument(_ data: Data, source: String, into output: inout [UInt16: DeviceDefinition]) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1,
              document.source.repository == "openrazer/openrazer",
              document.source.commit == sourceCommit
        else {
            throw RazerError.invalidArgument("目录 \(source) 的版本或来源不受支持")
        }
        for device in document.devices {
            guard let productId = UInt16(device.productId, radix: 16),
                  let capabilities = document.capabilitySets[device.capabilitySet],
                  (0...1_000_000).contains(device.waitMicroseconds)
            else {
                throw RazerError.invalidArgument("目录 \(source) 中的设备条目无效：\(device.productId)")
            }
            var transactions: [String: UInt8] = [:]
            for (builder, value) in device.transactions {
                guard let transaction = UInt8(value, radix: 16) else {
                    throw RazerError.invalidArgument("目录 \(source) 中的事务号无效")
                }
                transactions[builder] = transaction
            }
            var prefixes: [String: [[UInt8]]] = [:]
            for (builder, values) in device.builderArgumentPrefixes {
                prefixes[builder] = try values.map { try parseHex($0) }
            }
            let capabilitySet = Set(capabilities)
            completeClassicLedFacts(productId: productId, capabilities: capabilitySet,
                                    transactions: &transactions, prefixes: &prefixes)

            var sequences: [String: [CommandStep]] = [:]
            for (builder, steps) in device.commandSequences {
                sequences[builder] = try steps.map { step in
                    guard let txn = UInt8(step.transactionId, radix: 16),
                          let arg = UInt8(step.fixedArgument0, radix: 16)
                    else {
                        throw RazerError.invalidArgument("目录 \(source) 中的命令序列无效")
                    }
                    return CommandStep(transactionId: txn, fixedArgument0: arg)
                }
            }
            var matrix: MatrixDimensions?
            if let dimensions = device.matrixDimensions {
                guard dimensions.count == 2, (1...255).contains(dimensions[0]), (1...255).contains(dimensions[1]) else {
                    throw RazerError.invalidArgument("目录 \(source) 中的矩阵尺寸无效")
                }
                matrix = MatrixDimensions(rows: UInt8(dimensions[0]), columns: UInt8(dimensions[1]))
            }
            let definition = DeviceDefinition(
                productId: productId,
                displayName: device.displayName.trimmingCharacters(in: .whitespaces),
                category: try parseCategory(device.category),
                sourceCapabilities: capabilitySet,
                maximumDpi: device.maximumDpi,
                pollingRates: device.pollRates ?? [],
                matrixDimensions: matrix,
                deviceWait: TimeInterval(device.waitMicroseconds) / 1_000_000,
                transactions: transactions,
                builderArgumentPrefixes: prefixes,
                defaultStorage: try parseStorage(device.defaultStorage),
                defaultLedZone: try parseZone(device.defaultLedZone),
                commandSequences: sequences)
            guard output[productId] == nil else {
                throw RazerError.invalidArgument("重复的设备 ID \(definition.productIdText)")
            }
            output[productId] = definition
        }
    }

    /// Entries OpenSynapse admits on top of OpenRazer: read-only probes, aliases, and mice whose
    /// definitions come from the Synapse middleware and reuse the closest catalogued sibling.
    private static func addLocallyAdmittedDevices(_ devices: inout [UInt16: DeviceDefinition]) {
        // DeathAdder 2000 aliases: only the read half of the sibling is admitted.
        let readBuilders: Set<String> = [
            "razer_chroma_standard_get_firmware_version",
            "razer_chroma_standard_get_serial",
            "razer_chroma_standard_get_device_mode",
            "razer_chroma_misc_get_dpi_xy",
            "razer_chroma_misc_get_polling_rate",
            "razer_chroma_standard_get_led_brightness",
        ]
        if let sibling = devices[0x004F] {
            for productId: UInt16 in [0x005F, 0x004D] where devices[productId] == nil {
                let readOnly = sibling.transactions.filter { readBuilders.contains($0.key) }
                devices[productId] = sibling.with(
                    productId: productId,
                    displayName: "\(sibling.displayName)（只读探测）",
                    transactions: readOnly,
                    builderArgumentPrefixes: sibling.builderArgumentPrefixes.filter { readOnly[$0.key] != nil },
                    commandSequences: [:])
            }
        }

        for (siblingId, productId, name) in [
            (UInt16(0x00C0), UInt16(0x00DE), "Razer Viper V3 Pro SE (Wired)"),
            (UInt16(0x00C1), UInt16(0x00DF), "Razer Viper V3 Pro SE (Wireless)"),
        ] where devices[productId] == nil {
            if let sibling = devices[siblingId] {
                devices[productId] = sibling.with(productId: productId, displayName: name)
            }
        }

        let middlewareMice: [(UInt16, UInt16, String, Int, [Int])] = [
            (0x006A, 0x0063, "Razer Jugan", 7200, []),
            (0x0073, 0x0069, "Razer Mamba Hyperflux", 16000, [125, 500, 1000]),
            (0x006B, 0x0074, "Razer Abyssus Lite", 6400, []),
            (0x005A, 0x0075, "Razer Turret Mouse Xbox One Edition", 16000, [125, 500, 1000]),
            (0x0053, 0x0093, "Razer Naga Classic Edition", 16000, [125, 500, 1000]),
            (0x00BF, 0x00DD, "Razer Krakoff", 45000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00DB, 0x00E0, "Razer Orochi V2", 18000, [125, 500, 1000]),
            (0x00CD, 0x00E2, "Razer Basilisk V4 Pro (Wired)", 50000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00CD, 0x00E3, "Razer Basilisk V4 Pro (Wireless)", 50000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00C1, 0x00E5, "Razer Viper V4 Pro (Wired)", 50000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00C1, 0x00E6, "Razer Viper V4 Pro (Wireless)", 50000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00A8, 0x00E7, "Razer Naga V3 Pro (Wired)", 30000, [125, 500, 1000]),
            (0x00A8, 0x00E8, "Razer Naga V3 Pro (Wireless)", 30000, [125, 500, 1000]),
            (0x00CD, 0x00EA, "Razer Basilisk V4 HyperSpeed (Wireless)", 33000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00CD, 0x00EB, "Razer Basilisk V4 HyperSpeed (Wired)", 33000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00BF, 0x00EF, "Razer DeathAdder V4 Pro Carbon Fiber Edition (Wired)", 50000, [125, 500, 1000, 2000, 4000, 8000]),
            (0x00BF, 0x00F0, "Razer DeathAdder V4 Pro Carbon Fiber Edition (Wireless)", 50000, [125, 500, 1000, 2000, 4000, 8000]),
        ]
        for (siblingId, productId, name, maxDpi, rates) in middlewareMice where devices[productId] == nil {
            if let sibling = devices[siblingId] {
                devices[productId] = sibling.with(
                    productId: productId, displayName: name, maximumDpi: .some(maxDpi), pollingRates: rates)
            }
        }

        // Viper V3 HyperSpeed (product 184) uses a dedicated manifest upstream. Its commands are
        // the standard misc family on transaction 0x1F, so it is expressed as a catalog entry.
        if devices[0x00B8] == nil {
            let txn: UInt8 = 0x1F
            devices[0x00B8] = DeviceDefinition(
                productId: 0x00B8,
                displayName: "Razer Viper V3 HyperSpeed",
                category: .mouse,
                sourceCapabilities: [
                    "get_battery", "get_poll_rate", "set_poll_rate", "get_dpi_xy", "set_dpi_xy",
                    "get_idle_time", "set_idle_time", "get_dpi_stages", "set_dpi_stages",
                    "get_low_battery_threshold", "set_low_battery_threshold",
                ],
                maximumDpi: 30000,
                pollingRates: [125, 500, 1000],
                matrixDimensions: nil,
                deviceWait: 0.060,
                transactions: [
                    "razer_chroma_misc_get_battery_level": txn,
                    "razer_chroma_misc_get_polling_rate": txn,
                    "razer_chroma_misc_set_polling_rate": txn,
                    "razer_chroma_misc_get_dpi_xy": txn,
                    "razer_chroma_misc_set_dpi_xy": txn,
                    "razer_chroma_misc_get_idle_time": txn,
                    "razer_chroma_misc_set_idle_time": txn,
                    "razer_chroma_misc_get_dpi_stages": txn,
                    "razer_chroma_misc_set_dpi_stages": txn,
                    "razer_chroma_misc_get_low_battery_threshold": txn,
                    "razer_chroma_misc_set_low_battery_threshold": txn,
                ],
                builderArgumentPrefixes: ["razer_chroma_misc_get_dpi_xy": [[0x00]]],
                defaultStorage: .persistent,
                defaultLedZone: .all,
                commandSequences: [:],
                quirk: .viperProduct184)
        }
    }

    private static func completeClassicLedFacts(
        productId: UInt16,
        capabilities: Set<String>,
        transactions: inout [String: UInt8],
        prefixes: inout [String: [[UInt8]]]
    ) {
        func addPrefix(_ builder: String, _ prefix: [UInt8]) {
            var existing = prefixes[builder] ?? []
            if !existing.contains(prefix) {
                existing.append(prefix)
            }
            prefixes[builder] = existing
        }
        func addTransaction(_ builder: String, _ value: UInt8) {
            if transactions[builder] == nil {
                transactions[builder] = value
            }
        }

        let classicColorMice: Set<UInt16> = [0x001F, 0x0024, 0x0025, 0x0037, 0x003E, 0x003F, 0x0043, 0x0054, 0x005B]
        if classicColorMice.contains(productId) {
            addTransaction("razer_chroma_standard_set_led_rgb", 0x3F)
            addPrefix("razer_chroma_standard_set_led_rgb", [0x01])
        }
        // Anansi static and macro branches issue these as the second/third report.
        if productId == 0x010F {
            addTransaction("razer_chroma_standard_set_led_rgb", 0xFF)
            addPrefix("razer_chroma_standard_set_led_rgb", [0x01, 0x05])
            addTransaction("razer_chroma_standard_set_led_blinking", 0xFF)
            addPrefix("razer_chroma_standard_set_led_blinking", [0x00, 0x07])
        }
        if capabilities.contains("get_macro_effect") {
            addTransaction("razer_chroma_standard_get_led_effect", 0xFF)
            addPrefix("razer_chroma_standard_get_led_effect", [0x01, 0x07])
        }
        if capabilities.contains("get_logo_active") {
            addTransaction("razer_chroma_standard_get_led_effect", 0xFF)
            addPrefix("razer_chroma_standard_get_led_effect", [0x01, 0x04])
        }
    }

    private static func parseHex(_ value: String) throws -> [UInt8] {
        guard value.count % 2 == 0, !value.isEmpty, value.count <= 160 else {
            throw RazerError.invalidArgument("无效的十六进制参数 \(value)")
        }
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw RazerError.invalidArgument("无效的十六进制参数 \(value)")
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func parseCategory(_ value: String) throws -> DeviceCategory {
        switch value {
        case "accessory": .accessory
        case "keyboard": .keyboard
        case "laptop": .laptop
        case "mouse": .mouse
        case "mouse-mat": .mouseMat
        case "monitor": .monitor
        default: throw RazerError.invalidArgument("未知设备类别 \(value)")
        }
    }

    private static func parseStorage(_ value: String?) throws -> Storage {
        switch value {
        case nil, "01": .persistent
        case "00": .temporary
        default: throw RazerError.invalidArgument("未知存储类型 \(value ?? "")")
        }
    }

    private static func parseZone(_ value: String?) throws -> LedZone {
        guard let value else { return .all }
        guard let raw = UInt8(value, radix: 16), let zone = LedZone(rawValue: raw),
              [.all, .scrollWheel, .logo, .backlight, .macro, .game, .rightSide, .leftSide,
               .charging, .fastCharging, .fullyCharged].contains(zone)
        else {
            throw RazerError.invalidArgument("未知灯区 \(value)")
        }
        return zone
    }
}
