import RazerCore
import SwiftUI

extension ShapeStyle where Self == Color {
    static var razer: Color { Color(red: 0x44 / 255, green: 0xD6 / 255, blue: 0x2C / 255) }
}

/// A titled card. Pages lay these out in an adaptive grid.
struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct CardGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 640), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 16) {
            content
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

struct ApplyButton: View {
    let title: String
    let busy: Bool
    let action: () async -> Void

    init(_ title: String = "应用", busy: Bool, action: @escaping () async -> Void) {
        self.title = title
        self.busy = busy
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer()
            Button(title) { Task { await action() } }
                .buttonStyle(.borderedProminent)
                .tint(.razer)
                .disabled(busy)
        }
    }
}

struct BatteryBadge: View {
    let percent: Int?
    let charging: Bool?

    var body: some View {
        if let percent {
            HStack(spacing: 4) {
                Image(systemName: symbol(percent))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(percent <= 15 ? .red : .razer)
                Text("\(percent)%").monospacedDigit()
                if charging == true {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                }
            }
        }
    }

    private func symbol(_ value: Int) -> String {
        switch value {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Status line and error banner under a page header.
struct StatusBanner: View {
    let status: String?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                Label {
                    Text(error).textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else if let status {
                Label(status, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let battery: Int?
    let charging: Bool?
    let busy: Bool
    let reload: (() async -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.razer)
                .frame(width: 52, height: 52)
                .background(.razer.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            BatteryBadge(percent: battery, charging: charging).font(.title3)
            if busy {
                ProgressView().controlSize(.small)
            }
            if let reload {
                Button {
                    Task { await reload() }
                } label: {
                    Label("重新读取", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            }
        }
    }
}

/// Bridges RazerColor to the system color well.
struct RazerColorPicker: View {
    let title: String
    @Binding var color: RazerColor

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color.color }, set: { color = RazerColor($0) }), supportsOpacity: false)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(Int($0.rounded())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value.stepped(step), in: range)
        }
    }
}

extension Binding where Value == Double {
    /// Rounds to a step without `Slider(step:)`, which draws a tick mark per step on macOS.
    func stepped(_ step: Double) -> Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = ($0 / step).rounded() * step })
    }
}

extension View {
    func pagePadding() -> some View {
        padding(.horizontal, 24).padding(.vertical, 20)
    }
}
