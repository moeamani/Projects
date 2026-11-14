import SwiftUI
import AppKit
import ProjectCore

struct ContentView: View {
    @Binding var document: ProjectDocument
    @Environment(\.undoManager) private var undoManager
    @State private var undoTarget = UndoTarget()

    @State private var tab: MainTab = .tasks
    @State private var zoom: Zoom = .weeks
    @State private var selection = Set<Int>()
    @State private var lastClicked: Int?
    @State private var collapsed = Set<Int>()
    @State private var errorMessage: String?
    @State private var scrollX: CGFloat = 0
    @State private var todayTick = 0

    // MARK: Body

    var body: some View {
        let project = document.project
        let result = project.computeSchedule()
        VStack(spacing: 0) {
            projectBar(project, result)
            Divider()
            switch tab {
            case .tasks:
                tasksView(project, result)
            case .resources:
                ResourcesView(project: project,
                              onAdd: { edit("Add Resource") { $0.addResource() } },
                              onRename: renameResource,
                              onDelete: { uid in edit("Delete Resource") { $0.deleteResource(uid) } })
            }
        }
        .toolbar { toolbarContent }
        .alert("Can't do that", isPresented: Binding(get: { errorMessage != nil },
                                                      set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Header bar

    private func projectBar(_ project: ProjectData, _ result: ScheduleResult) -> some View {
        HStack(spacing: 12) {
            CommitField(value: project.name) { new in
                let name = new.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return false }
                edit("Rename Project") { $0.name = name }
                return true
            }
            .font(.headline)
            .frame(maxWidth: 260)
            Text("Starts").foregroundStyle(.secondary)
            DatePicker("", selection: Binding(get: { project.startDate.date },
                                              set: { d in edit("Change Project Start") { $0.startDate = Day(date: d).nextWorkingDay($0.workWeek) } }),
                       displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
            Text("Finishes \(result.finish.date.formatted(date: .abbreviated, time: .omitted))")
                .foregroundStyle(.secondary)
            workingDaysMenu(project)
            Spacer()
            Picker("View", selection: $tab) {
                ForEach(MainTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func workingDaysMenu(_ project: ProjectData) -> some View {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return Menu {
            ForEach(0..<7, id: \.self) { d in
                Toggle(names[d], isOn: Binding(
                    get: { project.workWeek.days.contains(d) },
                    set: { on in
                        var days = project.workWeek.days
                        if on { days.append(d) } else { days.removeAll { $0 == d } }
                        edit("Change Working Days") { $0.workWeek = WorkWeek(days: days) }
                    }))
            }
        } label: {
            Label("\(project.workWeek.days.count) working days/week", systemImage: "calendar.badge.clock")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose which weekdays count as working days")
    }

    // MARK: Tasks tab

    private func visibleRows(_ project: ProjectData, _ result: ScheduleResult) -> [Row] {
        var rows: [Row] = []
        var i = 0
        while i < project.tasks.count {
            let t = project.tasks[i]
            if let s = result.byUID[t.uid] { rows.append(Row(index: i, task: t, schedule: s)) }
            if collapsed.contains(t.uid) && project.isSummary(at: i) { i = project.subtreeEnd(at: i) } else { i += 1 }
        }
        return rows
    }

    private func tasksView(_ project: ProjectData, _ result: ScheduleResult) -> some View {
        let rows = visibleRows(project, result)
        let geo = TimelineGeometry(project: project, result: result, zoom: zoom)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                TaskGridHeader().frame(width: Col.total)
                Divider()
                TimelineHeader(geo: geo, zoom: zoom)
                    .offset(x: scrollX)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(height: Metrics.headerH)
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in gridRow(row, project) }
                    }
                    .frame(width: Col.total)
                    Divider()
                    ganttPane(project, rows, geo)
                }
            }
        }
    }

    private func gridRow(_ row: Row, _ project: ProjectData) -> some View {
        let uid = row.id
        return TaskGridRow(
            row: row,
            rowNumber: row.index + 1,
            predecessorText: project.predecessorText(forTaskAt: row.index),
            resources: project.resources,
            isSelected: selection.contains(uid),
            isCollapsed: collapsed.contains(uid),
            onSelect: { select(uid) },
            onToggleCollapse: { if collapsed.contains(uid) { collapsed.remove(uid) } else { collapsed.insert(uid) } },
            onName: { new in setName(uid, new) },
            onDuration: { new in setDuration(uid, new) },
            onStart: { day in setStart(uid, day) },
            onPercent: { new in setPercent(uid, new) },
            onPredecessors: { new in setPredecessors(uid, new) },
            onToggleResource: { ruid in toggleResource(uid, ruid) })
        .contextMenu {
            if row.task.startNoEarlierThan != nil {
                Button("Clear Start Constraint") { mutateTask(uid, "Clear Constraint") { $0.startNoEarlierThan = nil } }
            }
            Button("Delete Task", role: .destructive) { selection = [uid]; deleteSelected() }
        }
    }

    private func ganttPane(_ project: ProjectData, _ rows: [Row], _ geo: TimelineGeometry) -> some View {
        let positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        let selectedRows = Set(rows.enumerated().filter { selection.contains($0.element.id) }.map { $0.offset })
        let today = Day.today()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    GanttBackground(geo: geo, rowCount: rows.count, selectedRows: selectedRows, workWeek: project.workWeek,
                                    deps: dependencyLines(rows, positions, geo), today: today)
                    GanttBars(rows: rows, geo: geo,
                              onSelect: { select($0) },
                              onMove: { uid, day in setStart(uid, day) },
                              onResize: { uid, finish in resize(uid, toFinish: finish) })
                    Color.clear.frame(width: 1, height: 1).id("today")
                        .padding(.leading, max(0, geo.x(today)))
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: ScrollXKey.self, value: g.frame(in: .named("gantt")).minX)
                })
            }
            .coordinateSpace(name: "gantt")
            .onPreferenceChange(ScrollXKey.self) { scrollX = $0 }
            .onChange(of: todayTick) { _, _ in proxy.scrollTo("today", anchor: .center) }
        }
    }

    private func dependencyLines(_ rows: [Row], _ positions: [Int: Int], _ geo: TimelineGeometry) -> [DepLine] {
        func leftX(_ r: Row) -> CGFloat {
            r.task.durationDays == 0 && !r.schedule.isSummary ? geo.x(r.schedule.start) + geo.dayWidth / 2 - 7 : geo.x(r.schedule.start)
        }
        func rightX(_ r: Row) -> CGFloat {
            r.task.durationDays == 0 && !r.schedule.isSummary
                ? geo.x(r.schedule.start) + geo.dayWidth / 2 + 7
                : geo.x(r.schedule.finish) + geo.dayWidth
        }
        let byUID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var out: [DepLine] = []
        for row in rows where !row.schedule.isSummary {
            for link in row.task.predecessors {
                guard let pred = byUID[link.predecessorUID], !pred.schedule.isSummary,
                      let from = positions[pred.id], let to = positions[row.id] else { continue }
                let fromX = (link.type == .fs || link.type == .ff) ? rightX(pred) : leftX(pred)
                let atEnd = link.type == .ff || link.type == .sf
                out.append(DepLine(fromX: fromX, fromRow: from, toX: atEnd ? rightX(row) : leftX(row),
                                   toRow: to, arrivesAtEnd: atEnd))
            }
        }
        return out
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { addTask(milestone: false) } label: { Label("Add Task", systemImage: "plus") }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Add a task below the selection (⌘↩)")
            Button { addTask(milestone: true) } label: { Label("Add Milestone", systemImage: "diamond") }
                .help("Add a zero-length milestone")
        }
        ToolbarItemGroup {
            Button { edit("Outdent") { $0.outdent(selection) } } label: { Label("Outdent", systemImage: "decrease.indent") }
                .keyboardShortcut("[", modifiers: .command).disabled(selection.isEmpty)
                .help("Move the task up a level (⌘[)")
            Button { edit("Indent") { $0.indent(selection) } } label: { Label("Indent", systemImage: "increase.indent") }
                .keyboardShortcut("]", modifiers: .command).disabled(selection.isEmpty)
                .help("Make the task a subtask of the one above (⌘])")
            Button { edit("Move Up") { $0.moveUp(selection) } } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(selection.isEmpty)
            Button { edit("Move Down") { $0.moveDown(selection) } } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(selection.isEmpty)
        }
        ToolbarItemGroup {
            Button { linkSelected() } label: { Label("Link Tasks", systemImage: "link") }
                .disabled(selection.count < 2)
                .help("Chain the selected tasks finish-to-start")
            Button { edit("Unlink Tasks") { $0.removeLinks(among: selection) } } label: { Label("Unlink Tasks", systemImage: "scissors") }
                .disabled(selection.count < 2)
                .help("Remove links between the selected tasks")
            Button { deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                .keyboardShortcut(.delete, modifiers: .command).disabled(selection.isEmpty)
                .help("Delete the selected tasks (⌘⌫)")
        }
        ToolbarItemGroup {
            Picker("Zoom", selection: $zoom) {
                ForEach(Zoom.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Button { todayTick += 1 } label: { Label("Today", systemImage: "calendar") }
                .help("Scroll the chart to today")
        }
    }

    // MARK: Editing core (with undo)

    private func edit(_ name: String, _ change: (inout ProjectData) -> Void) {
        var copy = document.project
        change(&copy)
        apply(copy, actionName: name)
    }

    private func apply(_ new: ProjectData, actionName: String) {
        let old = document.project
        guard new != old else { return }
        document.project = new
        undoManager?.registerUndo(withTarget: undoTarget) { _ in apply(old, actionName: actionName) }
        undoManager?.setActionName(actionName)
        let live = Set(new.tasks.map(\.uid))
        selection = selection.filter { live.contains($0) }
        collapsed = collapsed.filter { live.contains($0) }
    }

    private func mutateTask(_ uid: Int, _ name: String, _ change: @escaping (inout ProjectTask) -> Void) {
        edit(name) { p in
            if let i = p.index(ofUID: uid) { change(&p.tasks[i]) }
        }
    }

    // MARK: Actions

    private func select(_ uid: Int) {
        let flags = NSEvent.modifierFlags
        let rows = visibleRows(document.project, document.project.computeSchedule())
        if flags.contains(.command) {
            if selection.contains(uid) { selection.remove(uid) } else { selection.insert(uid) }
        } else if flags.contains(.shift), let last = lastClicked,
                  let a = rows.firstIndex(where: { $0.id == last }), let b = rows.firstIndex(where: { $0.id == uid }) {
            selection = Set(rows[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [uid]
        }
        lastClicked = uid
    }

    private func addTask(milestone: Bool) {
        let project = document.project
        let after = project.topLevelIndices(of: selection).last ?? (project.tasks.isEmpty ? nil : project.tasks.count - 1)
        var newUID = 0
        edit(milestone ? "Add Milestone" : "Add Task") { p in
            newUID = p.addTask(after: after,
                               name: milestone ? "New Milestone" : "New Task",
                               durationDays: milestone ? 0 : 1)
        }
        selection = [newUID]
        lastClicked = newUID
    }

    private func deleteSelected() {
        let doomed = selection
        guard !doomed.isEmpty else { return }
        edit(doomed.count == 1 ? "Delete Task" : "Delete Tasks") { $0.deleteTasks(doomed) }
        selection = []
    }

    private func linkSelected() {
        let order = document.project.tasks.map(\.uid).filter { selection.contains($0) }
        var linked = 0
        edit("Link Tasks") { p in
            for (a, b) in zip(order, order.dropFirst()) {
                if p.addLink(fromUID: a, toUID: b) { linked += 1 }
            }
        }
        if linked == 0 {
            errorMessage = "Those tasks can't be linked. Summary tasks can't be linked, and a link can't make a loop."
        }
    }

    private func setName(_ uid: Int, _ text: String) -> Bool {
        mutateTask(uid, "Rename Task") { $0.name = text }
        return true
    }

    private func setDuration(_ uid: Int, _ text: String) -> Bool {
        guard let d = ProjectData.parseDuration(text) else {
            errorMessage = "“\(text)” isn't a duration. Try 5, 5d or 2w. Use 0 for a milestone."
            return false
        }
        mutateTask(uid, "Change Duration") { $0.durationDays = d }
        return true
    }

    private func setPercent(_ uid: Int, _ text: String) -> Bool {
        guard let v = ProjectData.parsePercent(text) else {
            errorMessage = "“\(text)” isn't a percentage between 0 and 100."
            return false
        }
        mutateTask(uid, "Change % Complete") { $0.percentComplete = v }
        return true
    }

    private func setStart(_ uid: Int, _ day: Day) {
        let target = day.nextWorkingDay(document.project.workWeek)
        mutateTask(uid, "Change Start") { $0.startNoEarlierThan = target }
    }

    private func resize(_ uid: Int, toFinish finish: Day) {
        let project = document.project
        guard let s = project.computeSchedule().byUID[uid] else { return }
        let week = project.workWeek
        let days = max(1, finish.nextWorkingDay(week).workIndex(week) - s.start.workIndex(week) + 1)
        mutateTask(uid, "Change Duration") { $0.durationDays = days }
    }

    private func setPredecessors(_ uid: Int, _ text: String) -> Bool {
        let project = document.project
        guard let i = project.index(ofUID: uid) else { return false }
        do {
            let links = try project.parsePredecessors(text, forTaskAt: i)
            mutateTask(uid, "Change Predecessors") { $0.predecessors = links }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func toggleResource(_ uid: Int, _ resourceUID: Int) {
        mutateTask(uid, "Assign Resource") { t in
            if let k = t.resourceUIDs.firstIndex(of: resourceUID) { t.resourceUIDs.remove(at: k) }
            else { t.resourceUIDs.append(resourceUID) }
        }
    }

    private func renameResource(_ uid: Int, _ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        edit("Rename Resource") { p in
            if let i = p.resources.firstIndex(where: { $0.uid == uid }) { p.resources[i].name = n }
        }
        return true
    }
}
