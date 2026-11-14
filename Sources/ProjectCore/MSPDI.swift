import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads and writes the Microsoft Project XML format ("MSPDI", File ▸ Save As ▸ XML Format in
/// Project for Windows). This is the app's native file format, so files round-trip with Windows.
public enum MSPDI {
    public enum Failure: LocalizedError {
        case invalidXML(String)
        case notProjectFile

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let m): return "The file isn't valid XML (\(m))."
            case .notProjectFile: return "This XML file isn't a Microsoft Project file. Binary .mpp files must first be saved as XML from Microsoft Project."
            }
        }
    }

    static let minutesPerDay = 480
    static let hoursPerDay = 8

    // MARK: - Writing

    public static func write(_ project: ProjectData) -> Data {
        let schedule = project.computeSchedule()
        var w = XMLWriter()
        w.raw("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>")
        w.open("Project", attributes: " xmlns=\"http://schemas.microsoft.com/project\"")
        w.el("SaveVersion", "14")
        w.el("Name", project.name)
        let now = nowString()
        w.el("CreationDate", now)
        w.el("LastSaved", now)
        w.el("ScheduleFromStart", "1")
        w.el("StartDate", "\(project.startDate.iso)T08:00:00")
        w.el("FinishDate", "\(schedule.finish.iso)T17:00:00")
        w.el("CalendarUID", "1")
        w.el("DefaultStartTime", "08:00:00")
        w.el("DefaultFinishTime", "17:00:00")
        w.el("MinutesPerDay", "\(minutesPerDay)")
        w.el("MinutesPerWeek", "\(minutesPerDay * 5)")
        w.el("DaysPerMonth", "20")

        writeCalendar(&w)

        w.open("Tasks")
        var counters: [Int] = []
        for (i, t) in project.tasks.enumerated() {
            let level = t.outlineLevel
            if counters.count < level { counters += [Int](repeating: 0, count: level - counters.count) }
            else { counters.removeLast(counters.count - level) }
            counters[level - 1] += 1
            let wbs = counters.map(String.init).joined(separator: ".")
            let sch = schedule.byUID[t.uid]
            let isSummary = project.isSummary(at: i)
            let isMilestone = !isSummary && t.durationDays == 0

            w.open("Task")
            w.el("UID", "\(t.uid)")
            w.el("ID", "\(i + 1)")
            w.el("Name", t.name)
            w.el("Type", "0")
            w.el("WBS", wbs)
            w.el("OutlineNumber", wbs)
            w.el("OutlineLevel", "\(level)")
            w.el("Priority", "500")
            if let sch {
                w.el("Start", "\(sch.start.iso)T08:00:00")
                w.el("Finish", "\(sch.finish.iso)T\(isMilestone ? "08" : "17"):00:00")
                w.el("Duration", durationString(days: sch.durationDays))
            } else {
                w.el("Duration", durationString(days: t.durationDays))
            }
            w.el("DurationFormat", "7")
            w.el("Milestone", isMilestone ? "1" : "0")
            w.el("Summary", isSummary ? "1" : "0")
            w.el("PercentComplete", "\(sch?.percentComplete ?? t.percentComplete)")
            if let c = t.startNoEarlierThan, !isSummary {
                w.el("ConstraintType", "4")   // Start No Earlier Than
                w.el("ConstraintDate", "\(c.iso)T08:00:00")
            }
            for l in t.predecessors where project.index(ofUID: l.predecessorUID) != nil {
                w.open("PredecessorLink")
                w.el("PredecessorUID", "\(l.predecessorUID)")
                w.el("Type", "\(l.type.rawValue)")
                w.el("CrossProject", "0")
                w.el("LinkLag", "\(l.lagDays * minutesPerDay * 10)")
                w.el("LagFormat", "7")
                w.close("PredecessorLink")
            }
            w.close("Task")
        }
        w.close("Tasks")

        w.open("Resources")
        for (i, r) in project.resources.enumerated() {
            w.open("Resource")
            w.el("UID", "\(r.uid)")
            w.el("ID", "\(i + 1)")
            w.el("Name", r.name)
            w.el("Type", "1")
            w.el("MaxUnits", "1")
            w.close("Resource")
        }
        w.close("Resources")

        w.open("Assignments")
        var assignmentUID = 1
        for t in project.tasks {
            for ruid in t.resourceUIDs where project.resources.contains(where: { $0.uid == ruid }) {
                w.open("Assignment")
                w.el("UID", "\(assignmentUID)")
                w.el("TaskUID", "\(t.uid)")
                w.el("ResourceUID", "\(ruid)")
                w.el("Units", "1")
                w.close("Assignment")
                assignmentUID += 1
            }
        }
        w.close("Assignments")
        w.close("Project")
        return Data(w.out.utf8)
    }

    private static func writeCalendar(_ w: inout XMLWriter) {
        w.open("Calendars")
        w.open("Calendar")
        w.el("UID", "1")
        w.el("Name", "Standard")
        w.el("IsBaseCalendar", "1")
        w.el("IsBaselineCalendar", "0")
        w.el("BaseCalendarUID", "-1")
        w.open("WeekDays")
        for dayType in 1...7 {
            w.open("WeekDay")
            w.el("DayType", "\(dayType)")
            let working = (2...6).contains(dayType)
            w.el("DayWorking", working ? "1" : "0")
            if working {
                w.open("WorkingTimes")
                for (from, to) in [("08:00:00", "12:00:00"), ("13:00:00", "17:00:00")] {
                    w.open("WorkingTime")
                    w.el("FromTime", from)
                    w.el("ToTime", to)
                    w.close("WorkingTime")
                }
                w.close("WorkingTimes")
            }
            w.close("WeekDay")
        }
        w.close("WeekDays")
        w.close("Calendar")
        w.close("Calendars")
    }

    static func durationString(days: Int) -> String { "PT\(days * hoursPerDay)H0M0S" }

    private static func nowString() -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: Date())
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    // MARK: - Reading

    public static func read(_ data: Data) throws -> ProjectData {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw Failure.invalidXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        guard root.name == "Project" else { throw Failure.notProjectFile }

        let perDay = max(root.int("MinutesPerDay") ?? minutesPerDay, 1)
        var name = root.string("Name") ?? root.string("Title") ?? "Project"
        if name.lowercased().hasSuffix(".xml") { name.removeLast(4) }
        let start = root.string("StartDate").flatMap { Day(iso: $0) } ?? Day.today()

        var project = ProjectData(name: name, startDate: start.nextWorkingDay())

        var usedUIDs = Set<Int>()
        var uidMap: [Int: Int] = [:]     // file UID → our UID
        var rawLinks: [(taskUID: Int, link: Link)] = []

        for t in root.child("Tasks")?.children(named: "Task") ?? [] {
            let level = t.int("OutlineLevel") ?? 1
            if level <= 0 || t.int("IsNull") == 1 { continue }     // project summary / blank rows
            guard let fileUID = t.int("UID") else { continue }

            var uid = fileUID
            if usedUIDs.contains(uid) { uid = (usedUIDs.max() ?? 0) + 1 }
            usedUIDs.insert(uid)
            uidMap[fileUID] = uid

            let milestone = t.int("Milestone") == 1
            var days = 1
            if milestone {
                days = 0
            } else if let d = t.string("Duration"), let minutes = parseMinutes(d, minutesPerDay: perDay) {
                days = Int((minutes / Double(perDay)).rounded())
                if days == 0 && minutes > 0 { days = 1 }
            }

            var constraint: Day?
            let ctype = t.int("ConstraintType") ?? 0
            if (ctype == 2 || ctype == 4), let cd = t.string("ConstraintDate").flatMap({ Day(iso: $0) }) {
                constraint = cd
            } else if t.int("Manual") == 1, let sd = t.string("Start").flatMap({ Day(iso: $0) }) {
                constraint = sd
            }

            project.tasks.append(ProjectTask(
                uid: uid,
                name: t.string("Name") ?? "",
                outlineLevel: level,
                durationDays: days,
                percentComplete: min(max(t.int("PercentComplete") ?? 0, 0), 100),
                startNoEarlierThan: constraint))

            for l in t.children(named: "PredecessorLink") {
                guard let puid = l.int("PredecessorUID") else { continue }
                let type = LinkType(rawValue: l.int("Type") ?? 1) ?? .fs
                var lag = 0
                if let raw = l.int("LinkLag"), ![19, 20].contains(l.int("LagFormat") ?? 7) {
                    lag = Int((Double(raw) / 10.0 / Double(perDay)).rounded())
                }
                rawLinks.append((uid, Link(predecessorUID: puid, type: type, lagDays: lag)))
            }
        }
        project.normalizeOutline()
        // Summary rows are computed from their subtasks, so drop whatever the file cached on them.
        for i in project.tasks.indices where project.isSummary(at: i) {
            project.tasks[i].percentComplete = 0
            project.tasks[i].durationDays = 1
            project.tasks[i].startNoEarlierThan = nil
        }

        for (taskUID, link) in rawLinks {
            guard let mapped = uidMap[link.predecessorUID], let i = project.index(ofUID: taskUID),
                  mapped != taskUID else { continue }
            var l = link
            l.predecessorUID = mapped
            project.tasks[i].predecessors.append(l)
        }

        var resourceMap: [Int: Int] = [:]
        for r in root.child("Resources")?.children(named: "Resource") ?? [] {
            guard let uid = r.int("UID"), r.int("IsNull") != 1,
                  let rname = r.string("Name"), !rname.isEmpty else { continue }
            resourceMap[uid] = uid
            project.resources.append(ProjectResource(uid: uid, name: rname))
        }

        for a in root.child("Assignments")?.children(named: "Assignment") ?? [] {
            guard let tuid = a.int("TaskUID").flatMap({ uidMap[$0] }),
                  let ruid = a.int("ResourceUID").flatMap({ resourceMap[$0] }),
                  let i = project.index(ofUID: tuid),
                  !project.tasks[i].resourceUIDs.contains(ruid) else { continue }
            project.tasks[i].resourceUIDs.append(ruid)
        }
        return project
    }

    /// Parses ISO-8601 durations such as "PT40H0M0S" or "P2DT4H" into minutes.
    static func parseMinutes(_ text: String, minutesPerDay: Int) -> Double? {
        guard text.hasPrefix("P") else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        for ch in text.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." { number.append(ch); continue }
            guard let v = Double(number) else { return nil }
            number = ""
            switch (ch, inTime) {
            case ("D", false): total += v * Double(minutesPerDay)
            case ("W", false): total += v * Double(minutesPerDay) * 5
            case ("H", true): total += v * 60
            case ("M", true): total += v
            case ("S", true): total += v / 60
            default: break
            }
        }
        return total
    }
}

// MARK: - Minimal XML tree + writer

final class XNode {
    let name: String
    var text = ""
    var children: [XNode] = []
    init(_ name: String) { self.name = name }

    func child(_ n: String) -> XNode? { children.first { $0.name == n } }
    func children(named n: String) -> [XNode] { children.filter { $0.name == n } }
    func string(_ n: String) -> String? {
        guard let c = child(n) else { return nil }
        let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    func int(_ n: String) -> Int? { string(n).flatMap { Int($0) } }
}

final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: XNode?
    private var stack: [XNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XNode(elementName)
        if let top = stack.last { top.children.append(node) } else if root == nil { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}

struct XMLWriter {
    var out = ""
    private var depth = 0

    mutating func raw(_ s: String) { out += s + "\n" }

    mutating func open(_ name: String, attributes: String = "") {
        out += String(repeating: " ", count: depth) + "<\(name)\(attributes)>\n"
        depth += 1
    }

    mutating func close(_ name: String) {
        depth -= 1
        out += String(repeating: " ", count: depth) + "</\(name)>\n"
    }

    mutating func el(_ name: String, _ value: String) {
        out += String(repeating: " ", count: depth) + "<\(name)>\(XMLWriter.escape(value))</\(name)>\n"
    }

    static func escape(_ s: String) -> String {
        var r = ""
        for u in s.unicodeScalars {
            switch u {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "'": r += "&apos;"
            default:
                if u.value >= 0x20 || u == "\t" || u == "\n" || u == "\r" { r.unicodeScalars.append(u) }
            }
        }
        return r
    }
}
