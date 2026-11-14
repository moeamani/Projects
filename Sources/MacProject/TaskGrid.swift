import SwiftUI
import ProjectCore

struct TaskGridHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("").frame(width: Col.id)
            Text("Task Name").frame(width: Col.name, alignment: .leading)
            Text("Duration").frame(width: Col.duration, alignment: .leading)
            Text("Start").frame(width: Col.start, alignment: .leading)
            Text("Finish").frame(width: Col.finish, alignment: .leading)
            Text("%").frame(width: Col.percent, alignment: .leading)
            Text("Predecessors").frame(width: Col.pred, alignment: .leading)
            Text("Resources").frame(width: Col.resources, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.04))
    }
}

struct TaskGridRow: View {
    let row: Row
    let rowNumber: Int
    let predecessorText: String
    let resources: [ProjectResource]
    let isSelected: Bool
    let isCollapsed: Bool
    let onSelect: () -> Void
    let onToggleCollapse: () -> Void
    let onName: (String) -> Bool
    let onDuration: (String) -> Bool
    let onStart: (Day) -> Void
    let onPercent: (String) -> Bool
    let onPredecessors: (String) -> Bool
    let onToggleResource: (Int) -> Void

    private var isSummary: Bool { row.schedule.isSummary }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rowNumber)")
                .foregroundStyle(.secondary)
                .frame(width: Col.id)
            nameCell.frame(width: Col.name, alignment: .leading)
            durationCell.frame(width: Col.duration, alignment: .leading)
            startCell.frame(width: Col.start, alignment: .leading)
            Text(row.schedule.finish.date.formatted(date: .numeric, time: .omitted))
                .frame(width: Col.finish, alignment: .leading)
            percentCell.frame(width: Col.percent, alignment: .leading)
            CommitField(value: predecessorText, onCommit: onPredecessors)
                .disabled(isSummary)
                .frame(width: Col.pred, alignment: .leading)
            resourceCell.frame(width: Col.resources, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 4)
        .frame(height: Metrics.rowH)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { _ in onSelect() })
    }

    private var nameCell: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: CGFloat(row.task.outlineLevel - 1) * 14, height: 1)
            if isSummary {
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            if row.task.durationDays == 0 && !isSummary {
                Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            CommitField(value: row.task.name, onCommit: onName)
                .fontWeight(isSummary ? .semibold : .regular)
        }
    }

    @ViewBuilder private var durationCell: some View {
        if isSummary {
            Text("\(row.schedule.durationDays)d").foregroundStyle(.secondary)
        } else {
            CommitField(value: "\(row.task.durationDays)d", onCommit: onDuration)
        }
    }

    @ViewBuilder private var startCell: some View {
        if isSummary {
            Text(row.schedule.start.date.formatted(date: .numeric, time: .omitted))
        } else {
            HStack(spacing: 2) {
                DatePicker("", selection: Binding(get: { row.schedule.start.date },
                                                  set: { onStart(Day(date: $0)) }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                if row.task.startNoEarlierThan != nil {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange)
                        .help("Start no earlier than this date. Right-click the row to clear.")
                }
            }
        }
    }

    @ViewBuilder private var percentCell: some View {
        if isSummary {
            Text("\(row.schedule.percentComplete)%").foregroundStyle(.secondary)
        } else {
            CommitField(value: "\(row.task.percentComplete)", onCommit: onPercent)
        }
    }

    private var resourceCell: some View {
        let names = resources.filter { row.task.resourceUIDs.contains($0.uid) }.map(\.name).joined(separator: ", ")
        return Menu {
            if resources.isEmpty {
                Button("Add resources in the Resources tab") {}.disabled(true)
            }
            ForEach(resources) { r in
                Toggle(r.name, isOn: Binding(get: { row.task.resourceUIDs.contains(r.uid) },
                                             set: { _ in onToggleResource(r.uid) }))
            }
        } label: {
            Text(names.isEmpty ? "—" : names).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .disabled(isSummary)
    }
}
