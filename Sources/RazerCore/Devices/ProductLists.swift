import Foundation

/// Products that OpenRazer does not catalogue and that OpenSynapse drives through the
/// protocol 25 families taken from the Synapse middleware.
public enum ProductLists {
    public static let chromaStandard: [UInt16: (name: String, category: DeviceCategory)] = [
        0x0063: ("Razer Jugan", .mouse),
        0x0069: ("Razer Mamba Hyperflux", .mouse),
        0x0074: ("Razer Abyssus Lite", .mouse),
        0x0075: ("Razer Turret Mouse Xbox One Edition", .mouse),
        0x0093: ("Razer Naga Classic Edition", .mouse),
        0x00B8: ("Razer Viper V3 HyperSpeed", .mouse),
        0x00CF: ("Razer HyperFlux V2", .mouse),
        0x00DD: ("Razer Krakoff", .mouse),
        0x00E0: ("Razer Orochi V2", .mouse),
        0x00E2: ("Razer Basilisk V4 Pro", .mouse),
        0x00E5: ("Razer Viper V4 Pro", .mouse),
        0x00E7: ("Razer Naga V3 Pro", .mouse),
        0x00EB: ("Razer Basilisk V4 HyperSpeed", .mouse),
        0x00EF: ("Razer DeathAdder V4 Pro Carbon Fiber Edition", .mouse),
        0x00F1: ("Razer Mouse Dock V2 Pro", .accessory),
        0x030A: ("Razer Chroma Addressable RGB Controller", .accessory),
        0x0F1F: ("Razer Chroma Addressable RGB Controller", .accessory),
        0x030C: ("Razer Key Light Chroma", .accessory),
        0x030D: ("Razer Aether Lamp Pro", .accessory),
        0x030E: ("Razer Aether Lamp", .accessory),
        0x030F: ("Razer Aether Light Bulb", .accessory),
        0x0310: ("Razer Aether Light Strip", .accessory),
        0x0316: ("Razer Aether Monitor Light Bar", .accessory),
        0x0317: ("Razer Aether Standing Light Bars", .accessory),
        0x0F27: ("Tomahawk Gaming Desktop", .accessory),
        0x0F28: ("Razer Raptor 27", .monitor),
        0x0F2C: ("Razer Chroma Wireless ARGB Controller", .accessory),
        0x0F35: ("Razer Hanbo AIO", .accessory),
        0x0F36: ("Razer Head Cushion Chroma", .accessory),
        0x0F3C: ("Razer PWM PC Fan Controller", .accessory),
        0x0F45: ("Esther", .accessory),
        0x0F51: ("Razer Core X V2", .accessory),
        0x0F52: ("Razer Thunderbolt 5 Dock Chroma", .accessory),
        0x0F59: ("Razer Monitor Stand Chroma", .accessory),
        0x0F5A: ("Razer Laptop Monitor Stand Chroma", .accessory),
        0x0F5C: ("Razer Handheld Dock Chroma", .accessory),
        0x0F64: ("Razer Soma Chroma", .accessory),
        0x0566: ("Razer Wireless Control Pod", .accessory),
        0x0F6A: ("Razer Base Station V3 Chroma", .accessory),
        0x0F6D: ("MarciT2H", .accessory),
    ]

    public static let keyboards25: [UInt16: String] = [
        0x02D0: "Razer Huntsman V3 Pro Tenkeyless 8KHz",
        0x02D1: "Razer Huntsman V3 Pro Mini 8KHz",
        0x02D8: "Razer Huntsman Signature Edition",
        0x02E4: "Razer Huntsman V3 HE Magnetic Mini 65% 8KHz",
        0x02E5: "Razer Huntsman V3 Tenkeyless 8KHz",
        0x02EA: "Razer Huntsman V3 HE Magnetic Tenkeyless 8KHz",
        0x0249: "Razer Pro Type",
        0x0251: "Razer Pikachu Limited Edition Backlit Keyboard",
        0x0277: "Razer Pro Type Ultra",
        0x028E: "Razer Cynosapro",
        0x02F0: "Razer BlackWidow V4 75% Xbox 25th Anniversary Edition",
        0x023E: "Razer Turret Keyboard Xbox One Edition",
        0x024F: "Razer BlackWidow X Tenkeyless",
        0x0250: "Razer Huntsman Essential",
        0x02B1: "Razer Huntsman V3 X Tenkeyless",
        0x02B3: "Razer BlackWidow V4 Pro 75%",
        0x02C4: "Razer Pro Type Ergo",
        0x02CC: "Razer BlackWidow V4 Low-profile HyperSpeed",
        0x02D4: "Razer BlackWidow V4 Low-profile Tenkeyless HyperSpeed",
        0x02E3: "Razer Reclusa X Mini 65%",
        0x02E6: "Razer Huntsman V3 Pro Low-Profile Tenkeyless 8KHz",
        0x02EB: "Razer Tartarus V2 Pro",
        0x02F4: "Razer Reclusa Mini 65%",
    ]

    /// Keyboards whose lighting runs on the older class 0x0F effect commands (no brightness).
    public static let legacyChromaKeyboards: Set<UInt16> = [
        0x023E, 0x024F, 0x0250, 0x02B1, 0x02B3, 0x02CC, 0x02D0, 0x02D1,
        0x02D4, 0x02D8, 0x02E3, 0x02E4, 0x02E5, 0x02EA, 0x02EB, 0x02F4,
    ]

    public static let headsetAudio: [UInt16: String] = [
        0x051A: "Razer Nari Ultimate",
        0x051C: "Razer Nari",
        0x051E: "Razer Nari",
        0x0520: "Razer USB Audio Controller",
        0x0521: "Razer Kraken Kitty Edition",
        0x0527: "Razer Kraken Ultimate",
        0x0528: "Razer BlackShark V2 Pro",
        0x0529: "Razer USB Sound Card",
        0x052D: "Razer Kraken V3 Pro",
        0x0533: "Razer Kraken V3 HyperSense",
        0x0539: "Razer Barracuda Pro",
        0x053B: "Razer Barracuda 2.4",
        0x053C: "Razer Barracuda",
        0x053E: "Razer Audio Mixer",
        0x0549: "Razer Kraken V3",
        0x0554: "Razer Kraken Kitty V2 Pro",
        0x0555: "Razer BlackShark V2 Pro",
        0x0565: "Razer BlackShark V2 HyperSpeed",
        0x0567: "Razer Kraken V4 Pro",
        0x056B: "Razer Kraken V4",
        0x056E: "Razer BlackShark V2 HyperSpeed",
        0x0576: "Razer BlackShark V3 Pro",
        0x0579: "Razer BlackShark V3",
        0x0583: "Razer Barracuda Pro",
        0x0584: "Razer Barracuda 2.4",
        0x0587: "Razer Kraken Kitty V3 Pro",
        0x0593: "Razer Barracuda V2 Pro",
        0x0309: "Razer Kraken BT Sanrio Limited Edition",
        0x0526: "Razer Kraken X USB",
        0x0530: "Razer Kraken BT Kitty Edition",
        0x0537: "Razer Kraken V3 X",
        0x0534: "Razer Kraken BT Sanrio Limited Edition",
        0x0560: "Razer Kraken Kitty V2",
        0x0562: "Razer Kraken Kitty V2 BT Quartz Edition",
        0x0532: "Razer Leviathan V2",
        0x055A: "Razer Nommo V2 Pro",
        0x055C: "Razer Nommo V2",
        0x055E: "Razer Nommo V2 X",
        0x0542: "Razer Seiren V2 Pro",
        0x0543: "Razer Seiren V2 X",
        0x056A: "Razer Seiren V3 Mini",
        0x0548: "Razer Leviathan V2 Pro",
        0x056D: "Razer Kraken V4 X",
        0x0F66: "Razer Marci",
        0x0F1B: "Razer Seiren Emote",
    ]

    static let speakerProducts: Set<UInt16> = [0x0532, 0x055A, 0x055C, 0x055E, 0x0548]
    static let microphoneProducts: Set<UInt16> = [0x0542, 0x0543, 0x056A, 0x0F1B]

    public static func audioCategory(_ productId: UInt16) -> DeviceCategory {
        microphoneProducts.contains(productId) ? .microphone
            : speakerProducts.contains(productId) ? .speaker : .headset
    }

    public struct KrakenModel: Sendable {
        public let name: String
        public let layout: KrakenLayout
        public let effects: [LightingEffect]
        public let writesColor: Bool
    }

    private static let kylieEffects: [LightingEffect] = [.off, .static, .spectrum, .breathingSingle, .breathingDual, .breathingTriple, .custom]

    public static let kraken: [UInt16: KrakenModel] = [
        0x0501: KrakenModel(name: "Razer Kraken 7.1", layout: .rainie, effects: [.off, .static], writesColor: false),
        0x0504: KrakenModel(name: "Razer Kraken 7.1 Chroma", layout: .rainie,
                            effects: [.off, .static, .spectrum, .breathingSingle, .custom], writesColor: true),
        0x0506: KrakenModel(name: "Razer Kraken 7.1", layout: .rainie, effects: [.off, .static], writesColor: false),
        0x0510: KrakenModel(name: "Razer Kraken 7.1 V2", layout: .kylie, effects: kylieEffects, writesColor: true),
        0x0520: KrakenModel(name: "Razer Kraken Tournament Edition", layout: .kylie, effects: kylieEffects, writesColor: true),
        0x0527: KrakenModel(name: "Razer Kraken Ultimate", layout: .kylie, effects: kylieEffects, writesColor: true),
        0x0560: KrakenModel(name: "Razer Kraken Kitty V2", layout: .kylie, effects: kylieEffects, writesColor: true),
    ]

    /// BlackShark V3 Pro product ids: OpenRazer lists 0576/0577, hardware enumerates 101B/101C.
    public static let blackSharkWired: Set<UInt16> = [0x0576, 0x101C]
    public static let blackSharkWireless: Set<UInt16> = [0x0577, 0x101B]
    public static let blackSharkObserved: Set<UInt16> = [0x101B, 0x101C]

    /// Headsets that speak the BlackShark 64-byte report 0x02 protocol, verified on hardware.
    /// `wireless` is the link byte to try first: the control hub relays to the headset on 0x80.
    public static let blackSharkProtocolHeadsets: [UInt16: (name: String, thx: Bool, ancWrite: Bool, wireless: Bool)] = [
        0x0567: ("Razer Kraken V4 Pro", false, false, false),
        0x0568: ("Razer Kraken V4 Pro（经控制终端）", false, false, true),
    ]

    /// Names for LampArray-only devices.
    public static let lampArrayNames: [UInt16: String] = [:]

    public static func blackSharkName(_ productId: UInt16) -> String {
        switch productId {
        case 0x0576, 0x101C: "Razer BlackShark V3 Pro (USB)"
        case 0x101B: "Razer BlackShark V3 Pro (2.4 GHz 接收器)"
        case 0x0577: "Razer BlackShark V3 Pro (2.4 GHz)"
        default: "Razer BlackShark V3 Pro"
        }
    }

    /// Total number of product ids the app recognises, for the overview.
    public static func recognisedProductCount(catalog: OpenRazerCatalog) -> Int {
        var ids = Set(catalog.devices.map(\.productId))
        ids.formUnion(chromaStandard.keys)
        ids.formUnion(keyboards25.keys)
        ids.formUnion(headsetAudio.keys)
        ids.formUnion(kraken.keys)
        ids.formUnion(blackSharkWired)
        ids.formUnion(blackSharkWireless)
        ids.formUnion(blackSharkProtocolHeadsets.keys)
        ids.formUnion(lampArrayNames.keys)
        return ids.count
    }
}
