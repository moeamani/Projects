import Foundation

public struct TaskSchedule: Equatable, Sendable {
    public var start: Day
    public var finish: Day
    /// Duration in working days (for summaries: the span of their subtasks).
    public var durationDays: Int
    public var percentComplete: Int
    public var isSummary: Bool
    public var isCritical: Bool
    public var slackDays: Int
    /// True when the task is part of (or downstream of) a circular dependency.
    public var inCycle: Bool
}

public struct ScheduleResult: Sendable {
    public var byUID: [Int: TaskSchedule]
    public var finish: Day
}

extension ProjectData {
    private struct Edge { let other: Int; let type: LinkType; let lag: Int }

    /// Forward/backward pass over a Mon–Fri calendar. Times are half-open working-day ranges [s, e).
    /// Links to or from summary tasks are ignored (link their subtasks instead).
    public func computeSchedule() -> ScheduleResult {
        let n = tasks.count
        let summary = (0..<n).map { isSummary(at: $0) }
        var uidToIndex: [Int: Int] = [:]
        for (i, t) in tasks.enumerated() { uidToIndex[t.uid] = i }

        var preds = [[Edge]](repeating: [], count: n)
        var succs = [[Edge]](repeating: [], count: n)
        for i in 0..<n where !summary[i] {
            for l in tasks[i].predecessors {
                guard let p = uidToIndex[l.predecessorUID], p != i, !summary[p] else { continue }
                preds[i].append(Edge(other: p, type: l.type, lag: l.lagDays))
                succs[p].append(Edge(other: i, type: l.type, lag: l.lagDays))
            }
        }

        // Topological order (Kahn). Leaves left over are in/after a cycle.
        var indeg = preds.map(\.count)
        var queue = (0..<n).filter { !summary[$0] && indeg[$0] == 0 }
        var order: [Int] = []
        var head = 0
        while head < queue.count {
            let u = queue[head]; head += 1
            order.append(u)
            for e in succs[u] {
                indeg[e.other] -= 1
                if indeg[e.other] == 0 { queue.append(e.other) }
            }
        }
        let ordered = Set(order)
        let leftovers = (0..<n).filter { !summary[$0] && !ordered.contains($0) }

        let projectStart = startDate.workIndex
        var s = [Int](repeating: projectStart, count: n)
        var e = [Int](repeating: projectStart, count: n)
        var done = [Bool](repeating: false, count: n)

        for i in order + leftovers {
            let d = tasks[i].durationDays
            var start = projectStart
            if let c = tasks[i].startNoEarlierThan { start = max(start, c.workIndex) }
            for edge in preds[i] where done[edge.other] {
                let p = edge.other
                switch edge.type {
                case .fs: start = max(start, e[p] + edge.lag)
                case .ss: start = max(start, s[p] + edge.lag)
                case .ff: start = max(start, e[p] + edge.lag - d)
                case .sf: start = max(start, s[p] + edge.lag - d)
                }
            }
            s[i] = start
            e[i] = start + d
            done[i] = true
        }

        let leaves = (0..<n).filter { !summary[$0] }
        let projectEnd = leaves.map { e[$0] }.max() ?? projectStart

        // Backward pass for slack / critical path.
        var lf = [Int](repeating: projectEnd, count: n)
        for u in order.reversed() {
            let d = tasks[u].durationDays
            for edge in succs[u] where ordered.contains(edge.other) {
                let j = edge.other
                let lfj = lf[j]
                let lsj = lf[j] - tasks[j].durationDays
                let bound: Int
                switch edge.type {
                case .fs: bound = lsj - edge.lag
                case .ss: bound = lsj - edge.lag + d
                case .ff: bound = lfj - edge.lag
                case .sf: bound = lfj - edge.lag + d
                }
                lf[u] = min(lf[u], bound)
            }
        }

        func finishDay(_ start: Int, _ end: Int) -> Day { Day(workIndex: max(end - 1, start)) }

        var result: [Int: TaskSchedule] = [:]
        for i in leaves {
            let inCycle = !ordered.contains(i)
            let slack = inCycle ? 0 : lf[i] - e[i]
            result[tasks[i].uid] = TaskSchedule(
                start: Day(workIndex: s[i]),
                finish: finishDay(s[i], e[i]),
                durationDays: tasks[i].durationDays,
                percentComplete: min(max(tasks[i].percentComplete, 0), 100),
                isSummary: false,
                isCritical: !inCycle && slack <= 0,
                slackDays: max(slack, 0),
                inCycle: inCycle)
        }

        // Summaries roll up their leaf descendants.
        for i in 0..<n where summary[i] {
            let range = (i + 1)..<subtreeEnd(at: i)
            let kids = range.filter { !summary[$0] }
            guard !kids.isEmpty else { continue }
            let minS = kids.map { s[$0] }.min()!
            let maxE = kids.map { e[$0] }.max()!
            let totalDur = kids.reduce(0) { $0 + tasks[$1].durationDays }
            let pct: Int
            if totalDur > 0 {
                pct = kids.reduce(0) { $0 + tasks[$1].durationDays * tasks[$1].percentComplete } / totalDur
            } else {
                pct = kids.reduce(0) { $0 + tasks[$1].percentComplete } / kids.count
            }
            let kidResults = kids.compactMap { result[tasks[$0].uid] }
            result[tasks[i].uid] = TaskSchedule(
                start: Day(workIndex: minS),
                finish: finishDay(minS, maxE),
                durationDays: maxE - minS,
                percentComplete: min(max(pct, 0), 100),
                isSummary: true,
                isCritical: kidResults.contains { $0.isCritical },
                slackDays: kidResults.map(\.slackDays).min() ?? 0,
                inCycle: kidResults.contains { $0.inCycle })
        }

        let finish = result.values.map(\.finish).max() ?? startDate
        return ScheduleResult(byUID: result, finish: finish)
    }
}
