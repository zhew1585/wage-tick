import AppKit
import SwiftUI

/// 时刻输入 (时:分)，无边框、无底色，放进 `Field` 里用：`Field("上班") { TimeInput(selection: $start) }`。
/// 用 AppKit 的文本式 `NSDatePicker`：SwiftUI 的 `DatePicker` 去不掉自带的边框，和设计稿的输入框叠在一起不好看。
/// 数字用 JetBrains Mono 14，方向键、数字键都能改。
struct TimeInput: NSViewRepresentable {
    @Binding var selection: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = AppFont.nsFont(.num, size: 14)
        picker.textColor = NSColor(Palette.ink)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection
        if picker.dateValue != selection {
            picker.dateValue = selection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}
