import Testing
@testable import RazerCore

// Invariants ported from OpenSynapse's OpenSynapse.Core.Tests. Upstream indexes the 91-byte
// Windows report; here every index is one lower because macOS passes report ID 0 separately.

private let catalog = OpenRazerCatalog.builtIn

private func device(_ pid: UInt16) -> DeviceDefinition {
    guard let definition = catalog.find(productId: pid) else {
        Issue.record("missing \(String(format: "%04X", pid))")
        fatalError()
    }
    return definition
}

@Suite struct CatalogTests {
    @Test func loadsThePinnedCatalogPlusAdmittedEntries() {
        #expect(catalog.upstreamCount == 259)
        for pid: UInt16 in [0x005F, 0x004D, 0x00DE, 0x00DF, 0x00E5, 0x00E6, 0x00EF, 0x00B8] {
            #expect(catalog.find(productId: pid) != nil)
        }
        #expect(catalog.find(productId: 0x005F)!.transactions.keys.allSatisfy { !$0.contains("_set_") })
    }

    @Test func recognisesEveryProductFamily() {
        #expect(ProductLists.recognisedProductCount(catalog: catalog) > 340)
    }

    @Test func defaultZonesComeFromDeviceFacts() {
        #expect(device(0x0203).defaultLedZone == .backlight)
        #expect(device(0x008F).defaultLedZone == .all)
        #expect(device(0x0F1A).defaultLedZone == .all)
        let zones = Set(CapabilityResolver.lightingZones(device(0x008F)).keys)
        #expect(zones.isSuperset(of: [.all, .backlight, .scrollWheel]))
    }

    @Test func tartarusPublishesLightingPerZone() {
        let zones = CapabilityResolver.lightingZones(device(0x022B))
        #expect(zones[.all]?.canWriteBrightness == false)
        #expect(zones[.all]?.effects.contains(.spectrum) == false)
        #expect(zones[.backlight]?.effects.contains(.spectrum) == true)
    }

    /// Every control the UI may show must be able to build its request.
    @Test func everyPublishedLightingControlBuildsItsRequest() throws {
        var failures: [String] = []
        for definition in catalog.devices {
            for (zone, caps) in CapabilityResolver.lightingZones(definition) {
                if caps.canReadBrightness, (try? LightingProtocol.getBrightness(definition, storage: definition.defaultStorage, zone: zone)) == nil {
                    failures.append("\(definition.productIdText) \(zone) brightness read")
                }
                if caps.canWriteBrightness,
                   (try? LightingProtocol.setBrightness(definition, storage: definition.defaultStorage, zone: zone, brightness: 128)) == nil {
                    failures.append("\(definition.productIdText) \(zone) brightness write")
                }
                for effect in caps.effects {
                    let settings = LightingSettings(effect: effect, zone: zone)
                    if (try? LightingProtocol.createEffectRequests(definition, settings)) == nil {
                        failures.append("\(definition.productIdText) \(zone) \(effect)")
                    }
                    let resolved = try? LightingProtocol.resolveEffectZone(definition, effect, zone: effect == .custom ? nil : zone)
                    if resolved != zone {
                        failures.append("\(definition.productIdText) \(zone) \(effect) resolves to \(String(describing: resolved))")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(20))")
    }

    /// Drives every published lighting control through the device layer the UI uses.
    @Test func everyPublishedEffectAppliesThroughTheDeviceLayer() async {
        var failures: [String] = []
        for definition in catalog.devices {
            let simulated = SimulatedDevice(productId: definition.productId, name: definition.displayName)
            let endpoint = FeatureEndpoint(interface: simulated.interfaces(registryBase: 1)[0], preference: .automatic, tag: "test")
            let device = OpenRazerDevice(definition: definition, endpoint: endpoint)
            for (zone, caps) in device.lightingZones {
                for effect in caps.effects {
                    do {
                        try await device.setLighting(LightingSettings(effect: effect, zone: zone))
                    } catch {
                        failures.append("\(definition.productIdText) \(zone) \(effect): \(error.localizedDescription)")
                    }
                }
                if caps.canWriteBrightness {
                    do { try await device.setBrightness(100, zone: zone) } catch {
                        failures.append("\(definition.productIdText) \(zone) brightness: \(error.localizedDescription)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(20))")
    }

    @Test func everyDeviceGetsAtLeastOneSafeProbe() {
        let missing = catalog.devices.filter { OpenRazerDevice.safeProbes($0).isEmpty }.map(\.productIdText)
        #expect(missing.isEmpty, "\(missing)")
    }
}

@Suite struct ReportTests {
    @Test func crcIsTheXorOfBytesTwoThrough87() throws {
        let report = try RazerReport(transactionId: 0x1F, dataSize: 0x02, commandClass: 0x07, commandId: 0x80)
        #expect(report.bytes.count == 90)
        #expect(report.bytes[1] == 0x1F)
        #expect(report.bytes[5] == 0x02)
        #expect(report.bytes[6] == 0x07)
        #expect(report.bytes[7] == 0x80)
        #expect(report.bytes[88] == 0x02 ^ 0x07 ^ 0x80)
    }

    @Test func argumentsBeyondTheDeclaredSizeNeedAnOptIn() {
        #expect(throws: RazerError.self) {
            try RazerReport(transactionId: 0, dataSize: 1, commandClass: 0, commandId: 0, arguments: [1, 2])
        }
    }

    @Test func viperV3ProDpiWriteMatchesOpenRazer() throws {
        let request = try MouseProtocol.setDpi(device(0x00C1), x: 1600, y: 800)
        #expect(request.report.transactionId == 0x1F)
        #expect(request.report.dataSize == 0x07)
        #expect(request.report.commandClass == 0x04)
        #expect(request.report.commandId == 0x05)
        #expect(Array(request.report.arguments) == [0x01, 0x06, 0x40, 0x03, 0x20, 0x00, 0x00])
    }

    @Test func viperProduct184WritesDpiWithStorageZero() throws {
        let request = try MouseProtocol.setDpi(device(0x00B8), x: 800, y: 800)
        #expect(request.report.bytes[8] == 0x00)
        let stages = try MouseProtocol.setDpiStages(device(0x00B8), DpiStages(activeStage: 1, stages: [
            DpiStage(number: 1, x: 400, y: 400), DpiStage(number: 2, x: 800, y: 800),
        ]))
        #expect(stages.report.dataSize == 3 + 2 * 7)
    }

    @Test(arguments: [(UInt8(0x01), 8000), (0x02, 4000), (0x04, 2000), (0x08, 1000), (0x10, 500), (0x40, 125)])
    func highPollingRateReadsArgumentOneOfAOneByteResponse(code: UInt8, expected: Int) throws {
        var response = try RazerReport(transactionId: 0x1F, dataSize: 0x01, commandClass: 0x00, commandId: 0xC0, arguments: [0x00])
        response.bytes[0] = 0x02
        response.bytes[9] = code
        response.bytes[88] = RazerReport.crc(response.bytes)
        #expect(try MouseProtocol.parsePollingRate(response, highRate: true) == expected)
    }

    @Test func legacyPollingRateReadsArgumentZero() throws {
        var response = try RazerReport(transactionId: 0x1F, dataSize: 0x01, commandClass: 0x00, commandId: 0x85, arguments: [0x02])
        response.bytes[0] = 0x02
        response.bytes[88] = RazerReport.crc(response.bytes)
        #expect(try MouseProtocol.parsePollingRate(response, highRate: false) == 500)
    }

    @Test func deathAdderV3WritesBothPollingRateReports() throws {
        let writes = try MouseProtocol.setPollingRate(device(0x00B2), hertz: 1000)
        #expect(writes.count == 2)
        #expect(writes.map { $0.report.bytes[8] } == [0x00, 0x01])
        for write in writes {
            #expect(write.report.transactionId == 0x1F)
            #expect(write.report.dataSize == 0x02)
            #expect(write.report.commandClass == 0x00)
            #expect(write.report.commandId == 0x40)
            #expect(write.report.bytes[9] == 0x08)
        }
    }
}

@Suite struct LightingTests {
    @Test(arguments: [UInt16(0x0F1A), 0x0F21])
    func dockWaveUsesTheResolved1FTransaction(pid: UInt16) throws {
        let request = try LightingProtocol.createEffect(device(pid), LightingSettings(effect: .wave))
        #expect(request.report.transactionId == 0x1F)
        #expect(request.report.commandClass == 0x0F)
        #expect(request.report.commandId == 0x02)
        #expect(request.report.hasValidCrc)
    }

    @Test func multiFamilyLightingRoutesByZone() throws {
        let mouse = device(0x008F)
        #expect(try LightingProtocol.createEffect(mouse, LightingSettings(effect: .spectrum, zone: .backlight)).builder
            .hasPrefix("razer_chroma_mouse_extended_"))
        #expect(try LightingProtocol.createEffect(mouse, LightingSettings(effect: .spectrum, zone: .all)).builder
            .hasPrefix("razer_chroma_extended_"))
    }

    @Test func standardCustomEffectUsesItsFixedStorage() throws {
        let keyboard = device(0x0203)
        let request = try LightingProtocol.createEffect(keyboard, LightingSettings(effect: .custom))
        #expect(Array(request.report.bytes[8...9]) == [0x05, 0x00])
        #expect(throws: RazerError.self) {
            try LightingProtocol.createEffect(keyboard, LightingSettings(effect: .custom, storage: .persistent))
        }
    }

    @Test(arguments: [UInt16(0x0044), 0x0203])
    func explicitDefaultCustomZoneUsesTheSameSelector(pid: UInt16) throws {
        let definition = device(pid)
        let implicit = try LightingProtocol.createEffectRequests(definition, LightingSettings(effect: .custom))
        let explicit = try LightingProtocol.createEffectRequests(definition, LightingSettings(effect: .custom, zone: definition.defaultLedZone))
        #expect(implicit.map(\.report) == explicit.map(\.report))
        #expect(throws: RazerError.self) {
            try LightingProtocol.createEffectRequests(definition, LightingSettings(effect: .custom, zone: .logo))
        }
    }

    @Test(arguments: [UInt16(0x0090), 0x00A7, 0x00A8])
    func nagaDefaultEffectsUseTheUpstreamFamily(pid: UInt16) throws {
        let naga = device(pid)
        let off = try LightingProtocol.createEffect(naga, LightingSettings(effect: .off))
        #expect(off.builder == "razer_chroma_standard_matrix_effect_none")
        #expect(off.report.transactionId == 0xFF)
        let spectrum = try LightingProtocol.createEffect(naga, LightingSettings(effect: .spectrum))
        #expect(spectrum.builder == "razer_chroma_mouse_extended_matrix_effect_spectrum")
        #expect(spectrum.report.transactionId == 0x1F)
    }
}

@Suite struct MiddlewareProtocolTests {
    @Test func krakenRequestMatchesThe37ByteMemoryLayout() {
        let report = KrakenProtocol.request(address: 0x172D, [0x05, 0xAA])
        #expect(report.count == 37)
        #expect(Array(report[..<7]) == [0x04, 0x40, 0x02, 0x17, 0x2D, 0x05, 0xAA])
        #expect(report[7...].allSatisfy { $0 == 0 })
    }

    @Test func krakenStaticWritesKylieColorThenEffect() {
        let reports = KrakenProtocol.staticColor(.kylie, RazerColor(0x11, 0x22, 0x33), writeColor: true)
        #expect(Array(reports[0][3...7]) == [0x17, 0x41, 0x11, 0x22, 0x33])
        #expect(Array(reports[1][3...5]) == [0x17, 0x2D, 0x01])
    }

    @Test func krakenBreathingUsesKylieColorBanks() throws {
        for (count, base, effect) in [(1, UInt16(0x1741), UInt8(0x0B)), (2, 0x1745, 0x19), (3, 0x174D, 0x29)] {
            let colors = Array([RazerColor(1, 2, 3), RazerColor(4, 5, 6), RazerColor(7, 8, 9)].prefix(count))
            let reports = try KrakenProtocol.breathing(.kylie, colors)
            #expect(reports.count == count + 1)
            #expect(reports[0][3] == base.high && reports[0][4] == base.low)
            #expect(reports.last![5] == effect)
        }
    }

    @Test func blackSharkFrameLayout() {
        let report = BlackSharkProtocol.create(0x99, 0x01, wireless: true, [7, 0])
        #expect(report.count == 64)
        #expect(report[0] == 0x02 && report[2] == 0x60 && report[6] == 6)
        #expect(report[9] == 0x80 && report[10] == 0x99 && report[12] == 0x01 && report[13] == 7)
        #expect(report[62] == report[0..<62].reduce(0, ^))
    }

    /// Attributes report captured from a Kraken V4 Pro (1532:0567).
    @Test func lampArrayAttributesFromKrakenV4Pro() {
        let bytes: [UInt8] = [0x31, 0x09, 0x00, 0x4C, 0x81, 0x00, 0x00, 0xB8, 0x88, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                              0x0B, 0x00, 0x00, 0x00, 0x20, 0x4E, 0x00, 0x00]
        let attributes = LampArrayProtocol.parseAttributes(bytes)
        #expect(attributes?.lampCount == 9)
        #expect(attributes?.kind == 11)
        #expect(attributes?.minUpdateInterval == 0.02)
        #expect(LampArrayProtocol.parseAttributes([0x31] + [UInt8](repeating: 0, count: 22)) == nil)
        #expect(LampArrayProtocol.fill(lampCount: 9, color: RazerColor(1, 2, 3), intensity: 200)
            == [0x35, 0x01, 0x00, 0x00, 0x08, 0x00, 1, 2, 3, 200])
    }

    @Test func protocol25PollingCodes() {
        #expect(KeyboardProtocol25.pollingCode(8000) == 0x01)
        #expect(KeyboardProtocol25.pollingCode(125) == 0x40)
        #expect(KeyboardProtocol25.pollingCode(333) == nil)
    }

    @Test func chromaEffectPayload() throws {
        let report = try ChromaProtocol.setEffect(3, .breathing, colors: [RazerColor(1, 2, 3), RazerColor(4, 5, 6)])
        #expect(report.commandClass == 0x10 && report.commandId == 0x03)
        #expect(Array(report.arguments) == [2, 0, 0, 2, 1, 2, 3, 4, 5, 6])
        let legacy = try ChromaProtocol.setLegacyEffect(3, .static, colors: [RazerColor(9, 8, 7)])
        #expect(legacy.commandClass == 0x0F && Array(legacy.arguments) == [1, 0, 1, 0, 0, 1, 9, 8, 7])
    }
}

@Suite struct SimulatorTests {
    @Test func demoDevicesResolveToTheirFamilies() async {
        let groups = DeviceDiscovery.groups(DeviceDiscovery.simulatedInterfaces())
        var kinds: [String] = []
        for group in groups {
            switch await DeviceDiscovery.resolve(group, preference: .automatic) {
            case .openRazer: kinds.append("openrazer")
            case .keyboard: kinds.append("keyboard")
            case .audio: kinds.append("audio")
            case .chroma: kinds.append("chroma")
            case .kraken: kinds.append("kraken")
            case .blackShark(_, let lighting): kinds.append(lighting == nil ? "blackshark" : "blackshark+lamps")
            case .lampArray: kinds.append("lamparray")
            case .unavailable(let device): kinds.append("unavailable:\(device.reason)")
            }
        }
        #expect(kinds.sorted() == ["audio", "blackshark", "blackshark+lamps", "chroma", "keyboard", "kraken", "openrazer", "openrazer"])
    }

    @Test func mouseRoundTripsDpiAndPolling() async throws {
        let group = DeviceDiscovery.groups(DeviceDiscovery.simulatedInterfaces()).first { $0.productId == 0x00C1 }!
        guard case .openRazer(let mouse) = await DeviceDiscovery.resolve(group, preference: .automatic) else {
            Issue.record("not resolved")
            return
        }
        let state = await mouse.readState()
        #expect(state.batteryPercent == 78)
        #expect(state.dpi?.x == 1600)
        #expect(state.errors.isEmpty, "\(state.errors)")
        let dpi = try await mouse.setDpi(x: 3200, y: 3200)
        #expect(dpi?.x == 3200)
        let rate = try await mouse.setPollingRate(4000)
        #expect(rate == 4000)
    }

    @Test func blackSharkReadsAndWritesSidetone() async throws {
        let group = DeviceDiscovery.groups(DeviceDiscovery.simulatedInterfaces()).first { $0.productId == 0x101B }!
        guard case .blackShark(let headset, _) = await DeviceDiscovery.resolve(group, preference: .automatic) else {
            Issue.record("not resolved")
            return
        }
        #expect(try await headset.readState().batteryPercent == 82)
        try await headset.setSidetone(9)
        #expect(try await headset.readState().sidetone == 9)
    }
}
