import AppKit
import RazerCore

/// `OpenSynapse --probe` scans the attached devices, reads their state with GET commands only,
/// prints a report plus the diagnostic log, and quits. Nothing is written to the devices.
@MainActor
enum ProbeRunner {
    static var requested: Bool { CommandLine.arguments.contains("--probe") }

    static func run() async {
        let preference = TransportPreference(rawValue: argument("--transport") ?? "") ?? .automatic
        let monitor = HIDMonitor()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let interfaces = monitor.interfaces()
        print("== Razer HID interfaces: \(interfaces.count), transport=\(preference.rawValue), inputMonitoring=\(HIDMonitor.inputMonitoringGranted)")
        for item in interfaces { print("  \(item.summary) loc=\(String(format: "%08X", item.locationId))") }

        for group in DeviceDiscovery.groups(interfaces) {
            print("\n== Device \(group.key)")
            switch await DeviceDiscovery.resolve(group, preference: preference) {
            case .openRazer(let device):
                print("OpenRazer: \(device.definition.displayName) via \(device.endpoint.pathDescription) \(device.endpoint.interface.usageText)")
                print("capabilities: \(device.capabilities.map(\.rawValue).sorted().joined(separator: ", "))")
                print("lighting zones: \(device.lightingZones.values.sorted { $0.zone < $1.zone }.map { "\($0.zone.displayName)[\($0.orderedEffects.map(\.rawValue).joined(separator: "/"))\($0.canWriteBrightness ? " +brightness" : "")]" }.joined(separator: " "))")
                let state = await device.readState()
                print("firmware=\(state.firmware ?? "-") serial=\(state.serial ?? "-") battery=\(state.batteryPercent.map(String.init) ?? "-") charging=\(state.charging.map { "\($0)" } ?? "-")")
                print("polling=\(state.pollingRate.map(String.init) ?? "-") dpi=\(state.dpi.map { "\($0.x)x\($0.y)" } ?? "-") stages=\(state.dpiStages.map { "\($0.activeStage)/\($0.stages.map { "\($0.x)" })" } ?? "-")")
                print("idle=\(state.idleSeconds.map(String.init) ?? "-") lowBattery=\(state.lowBatteryThreshold.map(String.init) ?? "-") brightness=\(state.brightness.map { "\($0.key.displayName)=\($0.value)" })")
                print("unsupported=\(state.unsupported.map(\.rawValue).sorted()) errors=\(state.errors)")
                for spec in rawRequests() {
                    await sendRaw(spec, device: device)
                }
                if CommandLine.arguments.contains("--mapping-test") {
                    await mappingTest(device)
                }
                if CommandLine.arguments.contains("--write-test") {
                    await writeTest(device, state)
                }
            case .keyboard(let device):
                let state = await device.readState()
                print("Keyboard25: \(device.name) fw=\(state.firmware ?? "-") battery=\(state.batteryPercent.map(String.init) ?? "-") polling=\(state.pollingRate.map(String.init) ?? "-") errors=\(state.errors)")
            case .audio(let device, let lighting):
                let state = await device.readState()
                print("Audio: \(device.name) via \(device.endpoint.pathDescription) kraken=\(lighting != nil) fw=\(state.firmware ?? "-") battery=\(state.batteryPercent.map(String.init) ?? "-") preset=\(state.eqPreset.map(String.init) ?? "-") bands=\(state.eqBands ?? []) errors=\(state.errors)")
            case .chroma(let device):
                let state = await device.readState()
                print("Chroma: \(device.name) effect=\(state.effect?.displayName ?? "-") brightness=\(state.brightnessPercent.map(String.init) ?? "-") errors=\(state.errors)")
            case .kraken(let device):
                print("Kraken lighting: \(device.model.name) (write-only channel, not exercised)")
            case .blackShark(let device, let lighting):
                let state = try? await device.readState()
                print("BlackShark-protocol: \(device.name) link=\(device.wireless ? "0x80" : "0x00") battery=\(state?.batteryPercent.map(String.init) ?? "-") charging=\(state?.charging.map { "\($0)" } ?? "-") sidetone=\(state?.sidetone.map(String.init) ?? "-") thx=\(state?.thx.map { "\($0)" } ?? "-") anc=\(state?.ancMode?.displayName ?? "-") gameChat=\(state?.gameChat.map(String.init) ?? "-") lampArray=\(lighting.map { "\($0.lampCount) lamps" } ?? "-")")
                if let lighting, CommandLine.arguments.contains("--lamp-test") { await lampTest(lighting) }
            case .lampArray(let device):
                print("LampArray: \(device.name) lamps=\(device.lampCount)")
                if CommandLine.arguments.contains("--lamp-test") { await lampTest(device) }
            case .unavailable(let device):
                print("Unavailable: \(device.name) recognised=\(device.recognised) reason=\(device.reason)")
            }
        }
        print("\n== Diagnostic log")
        print(DiagnosticLog.shared.exportText())
        fflush(stdout)
        NSApp.terminate(nil)
    }

    /// Reversible writes: change a setting, read it back, restore the original value.
    private static func writeTest(_ device: OpenRazerDevice, _ state: OpenRazerState) async {
        func report(_ name: String, _ body: () async throws -> String) async {
            do { print("write-test \(name): \(try await body())") } catch { print("write-test \(name): FAILED \(error.localizedDescription)") }
        }
        if let dpi = state.dpi, device.has(.dpiWrite) {
            await report("DPI") {
                let probe = dpi.x == 800 ? 1200 : 800
                let changed = try await device.setDpi(x: probe, y: probe)
                let restored = try await device.setDpi(x: dpi.x, y: dpi.y)
                return "\(dpi.x) → \(changed.map { "\($0.x)" } ?? "?") → \(restored.map { "\($0.x)" } ?? "?")"
            }
        }
        if let rate = state.pollingRate, device.has(.pollingRateWrite) {
            await report("polling") {
                let probe = rate == 1000 ? 500 : 1000
                let changed = try await device.setPollingRate(probe)
                let restored = try await device.setPollingRate(rate)
                return "\(rate) → \(changed.map(String.init) ?? "?") → \(restored.map(String.init) ?? "?")"
            }
        }
        for (zone, value) in state.brightness.sorted(by: { $0.key < $1.key }) {
            await report("\(zone.displayName) brightness") {
                let probe: UInt8 = value > 128 ? 64 : 200
                try await device.setBrightness(probe, zone: zone)
                let changed = try await device.getBrightness(zone: zone)
                try await device.setBrightness(value, zone: zone)
                let restored = try await device.getBrightness(zone: zone)
                return "\(value) → \(changed) → \(restored)"
            }
        }
        if let stages = state.dpiStages, device.has(.dpiStagesWrite) {
            await report("DPI stages (rewrite same table)") {
                try await device.setDpiStages(stages)
                return "ok"
            }
        }
    }

    /// `--raw "txn class cmd size [args…]"` (hex bytes, repeatable). Only GETs (cmd ≥ 0x80) are
    /// sent unless `--allow-set` is also given.
    private static func rawRequests() -> [[UInt8]] {
        var specs: [[UInt8]] = []
        let arguments = CommandLine.arguments
        for (index, value) in arguments.enumerated() where value == "--raw" && index + 1 < arguments.count {
            specs.append(arguments[index + 1].split(separator: " ").compactMap { UInt8($0, radix: 16) })
        }
        return specs
    }

    private static func sendRaw(_ spec: [UInt8], device: OpenRazerDevice) async {
        guard spec.count >= 4 else { return print("raw: need txn class cmd size") }
        guard spec[2] & 0x80 != 0 || CommandLine.arguments.contains("--allow-set") else {
            return print("raw \(spec.hexString): SET refused without --allow-set")
        }
        do {
            let report = try RazerReport(transactionId: spec[0], dataSize: spec[3], commandClass: spec[1], commandId: spec[2],
                                         arguments: Array(spec.dropFirst(4)), allowArgumentsBeyondDeclaredSize: true)
            let response = try await device.endpoint.query(report, wait: device.definition.deviceWait, label: "raw")
            print("raw \(spec.hexString): status=\(String(format: "%02X", response.status)) args=\(response.rawArguments.prefix(24).hexString)")
        } catch {
            print("raw \(spec.hexString): \(error.localizedDescription)")
        }
    }

    /// Red for three seconds, then back to the device's own effect.
    private static func lampTest(_ device: LampArrayDevice) async {
        do {
            try await device.setColor(RazerColor(255, 0, 0), brightness: 255)
            print("lamp-test \(device.name): red written")
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try await device.restoreDeviceEffect()
            print("lamp-test \(device.name): autonomous mode restored")
        } catch {
            print("lamp-test \(device.name): FAILED \(error.localizedDescription)")
        }
    }

    /// Lists every button on both layers, then changes the HyperShift-layer forward button to the
    /// middle button and restores it.
    private static func mappingTest(_ device: OpenRazerDevice) async {
        do {
            let buttons = try await device.mappableButtons()
            print("mapping: \(buttons.count) buttons")
            for button in buttons {
                let normal = try await device.buttonAssignment(button, layer: .normal)
                let shift = try await device.buttonAssignment(button, layer: .hyperShift)
                print("  \(MappingActions.buttonName(button)): \(MappingActions.describe(normal)) / \(MappingActions.describe(shift))")
            }
            guard buttons.contains(0x05) else { return print("mapping-test: no forward button") }
            let original = try await device.buttonAssignment(0x05, layer: .hyperShift)
            try await device.setButtonAssignment(0x05, layer: .hyperShift, ButtonAssignment(function: MappingFunction.mouseButton, data: [0x03]))
            let changed = try await device.buttonAssignment(0x05, layer: .hyperShift)
            try await device.setButtonAssignment(0x05, layer: .hyperShift, original)
            let restored = try await device.buttonAssignment(0x05, layer: .hyperShift)
            print("mapping-test: \(MappingActions.describe(original)) → \(MappingActions.describe(changed)) → \(MappingActions.describe(restored))")
        } catch {
            print("mapping-test: FAILED \(error.localizedDescription)")
        }
    }

    private static func argument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
