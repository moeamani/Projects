import Foundation

/// Dependency types. Raw values match the MSPDI `Type` codes.
public enum LinkType: Int, Sendable, CaseIterable {
    case ff = 0, fs = 1, sf = 2, ss = 3

    public var code: String {
        switch self {
        case .ff: return "FF"
        case .fs: return "FS"
        case .sf: return "SF"
        case .ss: return "SS"
        }
    }

    public init?(code: String) {
        switch code.uppercased() {
        case "FF": self = .ff
        case "FS": self = .fs
        case "SF": self = .sf
        case "SS": self = .ss
        default: return nil
        }
    }
}

public struct Link: Hashable, Sendable {
    public var predecessorUID: Int
    public var type: LinkType
    public var lagDays: Int
    public init(predecessorUID: Int, type: LinkType = .fs, lagDays: Int = 0) {
        self.predecessorUID = predecessorUID
        self.type = type
        self.lagDays = lagDays
    }
}

public struct ProjectTask: Identifiable, Hashable, Sendable {
    public var uid: Int
    public var name: String
    /// 1-based. A task is a "summary" when the next task has a deeper level.
    public var outlineLevel: Int
    /// Working days. 0 = milestone.
    public var durationDays: Int
    public var percentComplete: Int
    /// "Start no earlier than" constraint (set by typing a start date or dragging the bar).
    public var startNoEarlierThan: Day?
    public var predecessors: [Link]
    public var resourceUIDs: [Int]
    public var id: Int { uid }

    public init(uid: Int, name: String, outlineLevel: Int = 1, durationDays: Int = 1,
                percentComplete: Int = 0, startNoEarlierThan: Day? = nil,
                predecessors: [Link] = [], resourceUIDs: [Int] = []) {
        self.uid = uid
        self.name = name
        self.outlineLevel = outlineLevel
        self.durationDays = durationDays
        self.percentComplete = percentComplete
        self.startNoEarlierThan = startNoEarlierThan
        self.predecessors = predecessors
        self.resourceUIDs = resourceUIDs
    }
}

public struct ProjectResource: Identifiable, Hashable, Sendable {
    public var uid: Int
    public var name: String
    public var id: Int { uid }
    public init(uid: Int, name: String) { self.uid = uid; self.name = name }
}

public struct PredecessorError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public struct ProjectData: Equatable, Sendable {
    public var name: String
    public var startDate: Day
    public var tasks: [ProjectTask]
    public var resources: [ProjectResource]

    public init(name: String = "New Project",
                startDate: Day = Day.today().nextWorkingDay(),
                tasks: [ProjectTask] = [],
                resources: [ProjectResource] = []) {
        self.name = name
        self.startDate = startDate
        self.tasks = tasks
        self.resources = resources
    }

    // MARK: Outline structure

    public func index(ofUID uid: Int) -> Int? { tasks.firstIndex { $0.uid == uid } }

    public func isSummary(at i: Int) -> Bool {
        i + 1 < tasks.count && tasks[i + 1].outlineLevel > tasks[i].outlineLevel
    }

    /// Exclusive end index of the task's block (itself + all descendants).
    public func subtreeEnd(at i: Int) -> Int {
        var j = i + 1
        while j < tasks.count && tasks[j].outlineLevel > tasks[i].outlineLevel { j += 1 }
        return j
    }

    public var nextTaskUID: Int { (tasks.map(\.uid).max() ?? 0) + 1 }
    public var nextResourceUID: Int { (resources.map(\.uid).max() ?? 0) + 1 }

    /// Clamps outline levels so the first task is level 1 and no level jumps by more than 1.
    public mutating func normalizeOutline() {
        var prev = 0
        for i in tasks.indices {
            tasks[i].outlineLevel = min(max(tasks[i].outlineLevel, 1), prev + 1)
            prev = tasks[i].outlineLevel
        }
    }

    /// Indices of the selected tasks, excluding any whose ancestor is also selected.
    public func topLevelIndices(of uids: Set<Int>) -> [Int] {
        var result: [Int] = []
        var skipUntil = -1
        for i in tasks.indices where uids.contains(tasks[i].uid) {
            if i < skipUntil { continue }
            result.append(i)
            skipUntil = subtreeEnd(at: i)
        }
        return result
    }

    // MARK: Editing

    @discardableResult
    public mutating func addTask(after index: Int?, name: String = "New Task", durationDays: Int = 1) -> Int {
        let uid = nextTaskUID
        var level = 1
        var position = tasks.count
        if let i = index, tasks.indices.contains(i) {
            level = tasks[i].outlineLevel
            position = subtreeEnd(at: i)
        }
        tasks.insert(ProjectTask(uid: uid, name: name, outlineLevel: level, durationDays: durationDays), at: position)
        return uid
    }

    public mutating func indent(_ uids: Set<Int>) {
        for i in topLevelIndices(of: uids) where i > 0 && tasks[i].outlineLevel <= tasks[i - 1].outlineLevel {
            for j in i..<subtreeEnd(at: i) { tasks[j].outlineLevel += 1 }
        }
    }

    public mutating func outdent(_ uids: Set<Int>) {
        for i in topLevelIndices(of: uids) where tasks[i].outlineLevel > 1 {
            for j in i..<subtreeEnd(at: i) { tasks[j].outlineLevel -= 1 }
        }
    }

    public mutating func moveUp(_ uids: Set<Int>) {
        let ordered = topLevelIndices(of: uids).map { tasks[$0].uid }
        for uid in ordered {
            guard let i = index(ofUID: uid) else { continue }
            let level = tasks[i].outlineLevel
            var j = i - 1
            while j >= 0 && tasks[j].outlineLevel > level { j -= 1 }
            guard j >= 0, tasks[j].outlineLevel == level, !uids.contains(tasks[j].uid) else { continue }
            let end = subtreeEnd(at: i)
            let block = Array(tasks[i..<end])
            tasks.removeSubrange(i..<end)
            tasks.insert(contentsOf: block, at: j)
        }
    }

    public mutating func moveDown(_ uids: Set<Int>) {
        let ordered = topLevelIndices(of: uids).map { tasks[$0].uid }
        for uid in ordered.reversed() {
            guard let i = index(ofUID: uid) else { continue }
            let level = tasks[i].outlineLevel
            let end = subtreeEnd(at: i)
            guard end < tasks.count, tasks[end].outlineLevel == level, !uids.contains(tasks[end].uid) else { continue }
            let end2 = subtreeEnd(at: end)
            let block = Array(tasks[i..<end])
            tasks.removeSubrange(i..<end)
            tasks.insert(contentsOf: block, at: end2 - block.count)
        }
    }

    /// Deletes the tasks and (for summary tasks) all their subtasks, and removes dangling links.
    public mutating func deleteTasks(_ uids: Set<Int>) {
        var doomed = Set<Int>()
        for i in topLevelIndices(of: uids) {
            for j in i..<subtreeEnd(at: i) { doomed.insert(tasks[j].uid) }
        }
        tasks.removeAll { doomed.contains($0.uid) }
        for i in tasks.indices { tasks[i].predecessors.removeAll { doomed.contains($0.predecessorUID) } }
    }

    @discardableResult
    public mutating func addResource(name: String = "New Resource") -> Int {
        let uid = nextResourceUID
        resources.append(ProjectResource(uid: uid, name: name))
        return uid
    }

    public mutating func deleteResource(_ uid: Int) {
        resources.removeAll { $0.uid == uid }
        for i in tasks.indices { tasks[i].resourceUIDs.removeAll { $0 == uid } }
    }

    // MARK: Links

    /// True if adding `pred → succ` would create a loop.
    public func wouldCreateCycle(predUID: Int, succUID: Int) -> Bool {
        var stack = [predUID]
        var seen = Set<Int>()
        while let u = stack.popLast() {
            if u == succUID { return true }
            guard seen.insert(u).inserted, let i = index(ofUID: u) else { continue }
            stack.append(contentsOf: tasks[i].predecessors.map(\.predecessorUID))
        }
        return false
    }

    /// Adds a finish-to-start link. Returns false if invalid (summary, duplicate, or a loop).
    @discardableResult
    public mutating func addLink(fromUID: Int, toUID: Int, type: LinkType = .fs, lagDays: Int = 0) -> Bool {
        guard fromUID != toUID, let a = index(ofUID: fromUID), let b = index(ofUID: toUID),
              !isSummary(at: a), !isSummary(at: b),
              !tasks[b].predecessors.contains(where: { $0.predecessorUID == fromUID }),
              !wouldCreateCycle(predUID: fromUID, succUID: toUID) else { return false }
        tasks[b].predecessors.append(Link(predecessorUID: fromUID, type: type, lagDays: lagDays))
        return true
    }

    /// Removes every link whose both ends are in `uids`.
    public mutating func removeLinks(among uids: Set<Int>) {
        for i in tasks.indices where uids.contains(tasks[i].uid) {
            tasks[i].predecessors.removeAll { uids.contains($0.predecessorUID) }
        }
    }

    // MARK: Predecessor text ("3, 5SS+2d") — numbers are row numbers, as in MS Project

    public func predecessorText(forTaskAt i: Int) -> String {
        tasks[i].predecessors.compactMap { link -> String? in
            guard let p = index(ofUID: link.predecessorUID) else { return nil }
            var s = "\(p + 1)"
            if link.type != .fs { s += link.type.code }
            if link.lagDays != 0 { s += (link.lagDays > 0 ? "+" : "-") + "\(abs(link.lagDays))d" }
            return s
        }.joined(separator: ", ")
    }

    public func parsePredecessors(_ text: String, forTaskAt i: Int) throws -> [Link] {
        let tokens = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return [] }
        if isSummary(at: i) { throw PredecessorError(message: "Summary tasks can't have predecessors. Link their subtasks instead.") }

        var out: [Link] = []
        for token in tokens {
            let digits = token.prefix { $0.isASCII && $0.isNumber }
            guard let row = Int(digits) else {
                throw PredecessorError(message: "“\(token)” isn't valid. Use row numbers like 3, 5SS or 4FS+2d.")
            }
            guard row >= 1, row <= tasks.count else {
                throw PredecessorError(message: "There is no row \(row).")
            }
            let p = row - 1
            guard p != i else { throw PredecessorError(message: "A task can't depend on itself.") }
            guard !isSummary(at: p) else { throw PredecessorError(message: "Row \(row) is a summary task. Link one of its subtasks instead.") }

            var rest = String(token.dropFirst(digits.count)).replacingOccurrences(of: " ", with: "").uppercased()
            var type = LinkType.fs
            if rest.count >= 2, let t = LinkType(code: String(rest.prefix(2))) {
                type = t
                rest = String(rest.dropFirst(2))
            }
            var lag = 0
            if !rest.isEmpty {
                if rest.hasSuffix("D") { rest.removeLast() }
                guard rest.hasPrefix("+") || rest.hasPrefix("-"), let v = Int(rest) else {
                    throw PredecessorError(message: "“\(token)” isn't valid. Lag looks like +2d or -1d.")
                }
                lag = v
            }
            let puid = tasks[p].uid
            if wouldCreateCycle(predUID: puid, succUID: tasks[i].uid) {
                throw PredecessorError(message: "Linking to row \(row) would create a circular dependency.")
            }
            if !out.contains(where: { $0.predecessorUID == puid }) {
                out.append(Link(predecessorUID: puid, type: type, lagDays: lag))
            }
        }
        return out
    }

    // MARK: Input parsing

    /// "5", "5d", "2w" → working days. Returns nil if not understood.
    public static func parseDuration(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        var factor = 1
        for suffix in ["days", "day", "d"] where s.hasSuffix(suffix) { s.removeLast(suffix.count); break }
        for suffix in ["wks", "wk", "w"] where s.hasSuffix(suffix) { s.removeLast(suffix.count); factor = 5; break }
        guard let v = Int(s.trimmingCharacters(in: .whitespaces)), v >= 0, v <= 3650 else { return nil }
        return v * factor
    }

    public static func parsePercent(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let v = Int(s) else { return nil }
        return min(max(v, 0), 100)
    }

    // MARK: Sample

    public static func sample() -> ProjectData {
        var p = ProjectData(name: "My Project")
        p.resources = [ProjectResource(uid: 1, name: "Alex"), ProjectResource(uid: 2, name: "Sam")]
        p.tasks = [
            ProjectTask(uid: 1, name: "Planning", outlineLevel: 1),
            ProjectTask(uid: 2, name: "Define scope", outlineLevel: 2, durationDays: 3, percentComplete: 100, resourceUIDs: [1]),
            ProjectTask(uid: 3, name: "Create schedule", outlineLevel: 2, durationDays: 2, percentComplete: 50,
                        predecessors: [Link(predecessorUID: 2)], resourceUIDs: [1]),
            ProjectTask(uid: 4, name: "Plan approved", outlineLevel: 2, durationDays: 0,
                        predecessors: [Link(predecessorUID: 3)]),
            ProjectTask(uid: 5, name: "Execution", outlineLevel: 1),
            ProjectTask(uid: 6, name: "Build", outlineLevel: 2, durationDays: 10,
                        predecessors: [Link(predecessorUID: 4)], resourceUIDs: [1, 2]),
            ProjectTask(uid: 7, name: "Test", outlineLevel: 2, durationDays: 5,
                        predecessors: [Link(predecessorUID: 6)], resourceUIDs: [2]),
            ProjectTask(uid: 8, name: "Release", outlineLevel: 2, durationDays: 0,
                        predecessors: [Link(predecessorUID: 7)]),
        ]
        return p
    }
}
