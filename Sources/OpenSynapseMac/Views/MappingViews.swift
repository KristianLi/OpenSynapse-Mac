import RazerCore
import SwiftUI

/// Onboard button mapping: one row per button the firmware lists, on the normal or
/// HyperShift layer. Changes are written to the mouse's memory and read back.
struct ButtonMappingCard: View {
    @Bindable var model: OpenRazerModel
    @State private var editing: UInt8?

    var body: some View {
        Card(title: "按键设置", symbol: "computermouse.fill") {
            Picker("层", selection: $model.mappingLayer) {
                ForEach(MappingLayer.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(model.mappingLayer == .normal
                 ? "设置保存在鼠标里，不开这个应用也生效。"
                 : "按住设为 HyperShift 的按键时，切换到这一层的功能。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(model.mappingButtons, id: \.self) { button in
                    row(button)
                    if button != model.mappingButtons.last { Divider() }
                }
            }
        }
    }

    @ViewBuilder private func row(_ button: UInt8) -> some View {
        let layer = model.mappingLayer
        let current = model.assignments[layer]?[button]
        let original = model.originalAssignments[layer]?[button]
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.buttonName(button))
                Text(current.map(MappingActions.describe) ?? "无法读取")
                    .font(.caption)
                    .foregroundStyle(current != original ? Color.orange : Color.secondary)
            }
            Spacer()
            if let original, let current, current != original {
                Button("撤销") { Task { await model.applyMapping(button, layer: layer, original) } }
                    .buttonStyle(.borderless)
                    .help("恢复为打开应用时读到的设置：\(MappingActions.describe(original))")
            }
            if model.isLocked(button, layer: layer) {
                Image(systemName: "lock").foregroundStyle(.secondary)
                    .help("为避免失去左键点击，普通层的左键不能修改")
            } else {
                Button("修改…") { editing = button }
                    .disabled(model.busy || current == nil)
                    .popover(isPresented: Binding(get: { editing == button }, set: { if !$0 { editing = nil } })) {
                        MappingEditor(buttonName: model.buttonName(button), current: current) { assignment in
                            editing = nil
                            Task { await model.applyMapping(button, layer: layer, assignment) }
                        }
                    }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MappingEditor: View {
    let buttonName: String
    let apply: (ButtonAssignment) -> Void
    @State private var group: MappingGroup
    @State private var option: MappingOption
    @State private var modifier: UInt8

    init(buttonName: String, current: ButtonAssignment?, apply: @escaping (ButtonAssignment) -> Void) {
        self.buttonName = buttonName
        self.apply = apply
        let selection = current.flatMap(MappingActions.selection(for:))
        let group = selection?.group ?? .mouseButton
        _group = State(initialValue: group)
        _option = State(initialValue: selection?.option ?? MappingActions.options(group)[0])
        _modifier = State(initialValue: selection?.modifier ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(buttonName).font(.headline)
            Form {
                Picker("类型", selection: $group) {
                    ForEach(MappingGroup.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: group) { _, value in
                    option = MappingActions.options(value)[0]
                    modifier = 0
                }
                if MappingActions.options(group).count > 1 {
                    Picker("功能", selection: $option) {
                        ForEach(MappingActions.options(group)) { Text($0.name).tag($0) }
                    }
                }
                if group == .keyboardKey, option.code < 224 {
                    Picker("修饰键", selection: $modifier) {
                        ForEach(MappingActions.modifiers, id: \.mask) { Text($0.name).tag($0.mask) }
                    }
                }
            }
            .formStyle(.columns)
            let assignment = MappingActions.assignment(group, option, modifier: modifier)
            Text("将设为：\(MappingActions.describe(assignment))").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("写入鼠标") { apply(assignment) }
                    .buttonStyle(.borderedProminent)
                    .tint(.razer)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
