# OpenSynapse for Mac

English · [简体中文](README.zh-CN.md)

A macOS port of [OpenSynapse](https://github.com/A1mAssist/OpenSynapse) (Windows): control Razer peripherals on a Mac without Razer's own software. Native SwiftUI window app with a menu bar battery readout.

> Unofficial project, not affiliated with Razer Inc.

## Project status: early, tested on few devices

The protocol code covers the full OpenSynapse device list, but **only the devices in the first table have been tried on real hardware**. Everything else is implemented from the upstream code and passes unit tests against a simulated device, but has never been run against the real product on macOS. Expect some of those to misbehave, and please [report what you find](#help-test-a-device).

### Verified on real hardware

Writes were tested as change → read back → restore the original value.

| Device | Reads verified | Writes verified |
|---|---|---|
| Basilisk V4 Pro, wired (`1532:00E2`) | battery, charging, firmware, serial, DPI, DPI stages, polling rate (8000 Hz), sleep timer, low-battery warning, logo/wheel brightness, button assignments | DPI, polling rate, logo/wheel brightness, DPI stage table, onboard button mapping (14 buttons, normal and HyperShift layers) |
| Basilisk V3 (`1532:0099`) | firmware, serial, DPI, DPI stages, polling rate, brightness, scroll mode | notched / free-spin scroll mode |
| Kraken V4 Pro headset, USB cable (`1532:0567`) | battery, sidetone, noise-cancelling mode, game/chat balance | sidetone, game/chat balance, HID LampArray lighting |
| Kraken V4 Pro via its control hub, 2.4 GHz (`1532:0568`) | battery, charging, sidetone, noise-cancelling mode, game/chat balance | sidetone, game/chat balance, HID LampArray lighting (tested over USB) |

Mouse lighting effects were also confirmed by hand from the app with both Basilisk models connected.

Findings from these tests, already handled in the code:

- The Basilisk V4 Pro rejects the legacy polling-rate command it inherits from its catalog sibling; the app detects this and switches to the HyperPolling command.
- The Basilisk V4 Pro's notched / free-spin mode cannot be set from software (the firmware refuses both read and write); only the button behind the wheel changes it.
- The Kraken V4 Pro answers on link byte `0x00` over USB, and the control hub relays to the headset on `0x80` over 2.4 GHz.
- On the Basilisk V4 Pro the layer byte in button-assignment replies echoes the last write, so assignments are verified on function and data only. The button behind the wheel is itself a mappable button whose default function is "toggle scroll mode". The M1 edge button beside the left click is id `0x0E` (factory function: profile cycle) and the front, third side button is `0x80` (factory: off, since its AI Prompt Master action runs in Synapse); both were identified by pressing them. The same id means different buttons on different models (on the Basilisk V3, `0x0E` is the profile button underneath), so button names are per model: other mice get names from the factory function only, not a placement.
- The Kraken V4 Pro acknowledges THX writes without applying them, so THX is hidden; noise-cancelling level is not reported, so noise cancelling is read-only.

### Implemented but untested

| Family | Models | Controls |
|---|---|---|
| OpenRazer catalog (mice / keyboards / laptops / accessories) | 259 + 22 local additions | onboard button mapping on mice that answer the button-list command, battery, polling rate (up to 8K), DPI, DPI stages, sleep timer, low-battery warning, per-zone effects and brightness, whole-keyboard colour, scroll mode / acceleration / Smart Reel, keyswitch optimisation, HyperPolling indicator |
| Protocol 25 keyboards (Huntsman V3, Pro Type, …) | 23 | firmware/serial, battery, game mode, polling rate, Chroma effect and brightness |
| Protocol 25 audio (Kraken, BlackShark V2, Barracuda, Nari, Nommo, Seiren, …) | 45 | EQ preset and 10/8 bands, bass, mic mute/volume/noise suppression, audio source, ANC |
| Chroma 0x10 lighting accessories (Aether lamps, docks, stands, ARGB controllers, …) | 40 | effect, colour, brightness, battery |
| Kraken lighting (older models) | 7 | off, static, spectrum, 1/2/3-colour breathing, custom |
| BlackShark V3 Pro | 1 | battery, charging, sidetone, THX, ANC, game/chat balance |
| HID LampArray lighting | auto-detected | colour, brightness, off, restore the device's own effect |

Not tested yet even on the verified devices: wireless mice through their 2.4 GHz receiver, the USB control-transfer fallback (all tests ran over HID), and keyboards that need the Input Monitoring permission.

Like upstream, a page only shows controls that the device's catalog entry declares and that answer on the resolved interface. Controls whose read the firmware refuses are hidden.

**Not ported** (depend on Windows or Razer components): Blade laptop fan/performance/GPU switching, the THX native audio component, the Windows filter driver, macro recording, Chroma REST, Philips Hue, Bluetooth LE protocol 30.

## Differences from the Windows version

- **Transport:** IOKit HID feature reports by default, the same reports as the Windows version. If a HID interface cannot be opened (keyboard interfaces need the Input Monitoring permission), the app falls back to USB control transfers, the channel OpenRazer uses on Linux, which needs no permission. Settings can pin either path.
- The report format is the same; macOS passes report ID 0 separately, so byte indexes are one lower than in the upstream C# code.
- Onboard button mapping is offered on any mouse that answers the button-list query (upstream limits it to its middleware-admitted models), and the normal-layer left button is locked so a mapping cannot take away the click.
- Additions not in upstream: Kraken V4 Pro and its control hub, HID LampArray lighting, HyperPolling detection for 8 kHz mice whose catalog entry uses the legacy command.

## Build and run

Requires macOS 14+ and Swift 6 (Xcode or the Command Line Tools).

```bash
scripts/build-app.sh
```

This builds `dist/OpenSynapse.app` with an ad-hoc signature. During development you can also run `swift run OpenSynapseMac`.

Run the tests (with only the Command Line Tools installed, point Swift at the Testing framework):

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F
```

The tests port the upstream protocol invariants (DPI and polling bytes, lighting builder routing, Kraken and BlackShark frames) and build and send every lighting control of every catalog device to a simulated device.

## Usage notes

- Because of the ad-hoc signature, the first launch may need right-click → Open.
- Quit other Razer control software (Razer Synapse, Razer macOS) so two programs do not drive the same device at once.
- With no device attached, turn on **demo mode** in Settings to preview every page with simulated devices.
- The **Diagnostics** page logs every command sent and every reply, and lists all Razer HID interfaces.

## Help test a device

If you own a device from the untested list, a read-only report helps a lot:

```bash
dist/OpenSynapse.app/Contents/MacOS/OpenSynapse --probe
```

It scans the attached Razer devices, reads their state with GET commands only, prints the diagnostic log and exits; nothing is written. Open an issue with the output and the model name. **Remove the serial numbers from the output before posting.**

Two more options exist for checking writes, both of which restore the original values:

- `--probe --write-test` changes DPI, polling rate and brightness, reads them back and restores them.
- `--probe --lamp-test` turns HID LampArray lights red for 3 seconds, then returns them to the device's own effect.

`--snapshot <dir>` renders every page into PNG files using the demo devices (add `--real` for the attached devices, read-only).

## Project layout

```
Sources/RazerUSB/        C: USB control transfers (IOUSBDeviceInterface)
Sources/RazerCore/       protocols, device catalog, capability resolution, IOKit transport, simulator
  Resources/*.json       OpenRazer device catalog (as packaged by OpenSynapse)
Sources/OpenSynapseMac/  SwiftUI app
Tests/RazerCoreTests/    protocol tests
```

## License

The source code is under the [MIT License](LICENSE) and keeps the OpenSynapse copyright notice, since the protocol layer is a Swift translation of its C# code.

The device catalog data in `Sources/RazerCore/Resources/` derives from [OpenRazer](https://github.com/openrazer/openrazer) and stays under GPL-2.0-or-later. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project is not affiliated with Razer Inc. and contains no Razer software, drivers or firmware. Razer and related product names are trademarks of their respective owners and are used only to identify compatible hardware.
