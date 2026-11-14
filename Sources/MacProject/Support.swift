import SwiftUI
import ProjectCore

enum Metrics {
    static let rowH: CGFloat = 28
    static let headerH: CGFloat = 44
}

enum Col {
    static let id: CGFloat = 34
    static let name: CGFloat = 210
    static let duration: CGFloat = 56
    static let start: CGFloat = 104
    static let finish: CGFloat = 92
    static let percent: CGFloat = 46
    static let pred: CGFloat = 86
    static let resources: CGFloat = 96
    static var total: CGFloat { id + name + duration + start + finish + percent + pred + resources + 8 }
}

enum Zoom: String, CaseIterable, Identifiable {
    case days = "Days", weeks = "Weeks", months = "Months"
    var id: String { rawValue }
    var dayWidth: CGFloat {
        switch self {
        case .days: return 28
        case .weeks: return 12
        case .months: return 3.5
        }
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case tasks = "Tasks", resources = "Resources"
    var id: String { rawValue }
}

/// One visible row of the task table / Gantt chart.
struct Row: Identifiable {
    let index: Int
    let task: ProjectTask
    let schedule: TaskSchedule
    var id: Int { task.uid }
}

/// Identity token for the undo manager.
final class UndoTarget {}

/// A text field that commits on Return or when it loses focus. `onCommit` returns false to reject
/// the input, which restores the previous text.
struct CommitField: View {
    let value: String
    var alignment: TextAlignment = .leading
    let onCommit: (String) -> Bool

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, new in text = new }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        guard text != value else { return }
        if !onCommit(text) { text = value }
    }
}

struct ScrollXKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
