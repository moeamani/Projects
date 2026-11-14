import Foundation

/// Reads native Microsoft Project .mpp files saved by Project 2010 or newer ("MPP14" layout).
///
/// The format is undocumented; this implementation follows the structure reverse-engineered by the
/// open-source MPXJ project and covers what this app models: tasks, outline, durations, dates,
/// links, resources, assignments and the working calendar. Everything else in the file is ignored.
public enum MPP {
    public enum Failure: LocalizedError {
        case notMPP
        case unsupportedVersion
        case damaged

        public var errorDescription: String? {
            switch self {
            case .notMPP:
                return "This doesn't look like a Microsoft Project file."
            case .unsupportedVersion:
                return "This .mpp was saved by Project 2007 or older (or is password-protected). In Microsoft Project, use File ▸ Save As ▸ XML Format, then open that file here."
            case .damaged:
                return "The .mpp file couldn't be read. In Microsoft Project, use File ▸ Save As ▸ XML Format, then open that file here."
            }
        }
    }

    public static func isMPP(_ data: Data) -> Bool { CompoundFile.looksLikeOLE(data) }

    // MARK: - Public entry point

    public static func read(_ data: Data) throws -> ProjectData {
        guard let cfb = CompoundFile(data) else { throw Failure.notMPP }
        // The project data lives in a storage named "   114" (three spaces + 114) for Project 2010+.
        var storage: String?
        for name in cfb.streamNames where name.hasSuffix("/Props") {
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2 && parts[0].contains("114") { storage = String(parts[0]) }
        }
        guard let dir = storage else { throw Failure.unsupportedVersion }
        let file = Container(cfb: cfb, dir: dir)
        guard file.stream("TBkndTask", "FixedData") != nil, file.stream("TBkndTask", "Var2Data") != nil else {
            throw Failure.unsupportedVersion
        }
        return try file.buildProject()
    }

    // MARK: - Container

    private struct Container {
        let cfb: CompoundFile
        let dir: String
        let version: Int
        let props: [Int: [UInt8]]
        let minutesPerDay: Int

        init(cfb: CompoundFile, dir: String) {
            self.cfb = cfb
            self.dir = dir
            // "Microsoft.Project 16.0" in the CompObj stream gives the application version.
            var v = 14
            if let comp = cfb.read("\u{01}CompObj") {
                let text = String(decoding: comp, as: UTF8.self)
                if let r = text.range(of: "Microsoft.Project ") {
                    let digits = text[r.upperBound...].prefix { $0.isNumber }
                    if let n = Int(digits) { v = n }
                }
            }
            version = v
            props = Container.parseProps(cfb.read(dir + "/Props") ?? [])
            let mpd = (props[37748765] ?? []).i32(0)
            minutesPerDay = mpd > 0 ? mpd : 480
        }

        func stream(_ storage: String, _ name: String) -> [UInt8]? { cfb.read("\(dir)/\(storage)/\(name)") }

        static func parseProps(_ b: [UInt8]) -> [Int: [UInt8]] {
            var map: [Int: [UInt8]] = [:]
            guard b.count >= 16 else { return map }
            let count = b.u16(12)
            var o = 16
            var n = 0
            while n < count, o + 12 <= b.count {
                let size = b.i32(o), key = b.i32(o + 4)
                o += 12
                guard size >= 1, o + size <= b.count else { break }
                map[key] = b.slice(o, size)
                o += size + (size & 1)
                n += 1
            }
            return map
        }

        // MARK: Building the project

        func buildProject() throws -> ProjectData {
            let rawTasks = readTasks()
            guard !rawTasks.isEmpty else { throw Failure.damaged }
            let week = readWorkWeek()

            var project = ProjectData(name: "Project", startDate: Day.today(), workWeek: week)
            if let root = rawTasks.first(where: { $0.uid == 0 || $0.level == 0 }), !root.name.isEmpty {
                project.name = root.name
            }

            var uidMap: [Int: Int] = [:]
            for t in rawTasks.sorted(by: { $0.id < $1.id }) where t.uid != 0 && t.level >= 1 {
                var days = 1
                if t.milestone {
                    days = 0
                } else {
                    let raw = t.manual ? (t.manualDuration ?? t.scheduledDuration) : (t.scheduledDuration ?? t.manualDuration)
                    if let raw = raw, raw >= 0 {
                        days = Int((Double(raw) / 10.0 / Double(minutesPerDay)).rounded())
                        if days == 0 && raw > 0 { days = 1 }
                    }
                }
                var constraint: Day?
                if t.manual, let s = t.start {
                    constraint = s
                } else if t.constraintType == 2 || t.constraintType == 4 {
                    constraint = t.constraintDate
                }
                uidMap[t.uid] = t.uid
                project.tasks.append(ProjectTask(uid: t.uid, name: t.name, outlineLevel: t.level,
                                                 durationDays: days, percentComplete: min(max(t.percent, 0), 100),
                                                 startNoEarlierThan: constraint))
            }
            guard !project.tasks.isEmpty else { throw Failure.damaged }
            project.normalizeOutline()
            for i in project.tasks.indices where project.isSummary(at: i) {
                project.tasks[i].percentComplete = 0
                project.tasks[i].durationDays = 1
                project.tasks[i].startNoEarlierThan = nil
            }

            // Project start: the project property, else the earliest task date.
            if let s = props[37748738].flatMap({ Container.day(from: $0, at: 0) }) {
                project.startDate = s.nextWorkingDay(week)
            } else if let s = rawTasks.compactMap({ $0.start ?? $0.scheduledStart }).min() {
                project.startDate = s.nextWorkingDay(week)
            } else {
                project.startDate = Day.today().nextWorkingDay(week)
            }

            // Links
            for r in readRelations() {
                guard uidMap[r.pred] != nil, uidMap[r.succ] != nil, r.pred != r.succ,
                      let i = project.index(ofUID: r.succ) else { continue }
                let type = LinkType(rawValue: r.type) ?? .fs
                if project.tasks[i].predecessors.contains(where: { $0.predecessorUID == r.pred }) { continue }
                project.tasks[i].predecessors.append(Link(predecessorUID: r.pred, type: type, lagDays: lagDays(r.duration, r.units)))
            }
            // Drop any links that would form a loop (corrupt or hand-edited files).
            for i in project.tasks.indices {
                let links = project.tasks[i].predecessors
                project.tasks[i].predecessors = []
                for l in links where !project.wouldCreateCycle(predUID: l.predecessorUID, succUID: project.tasks[i].uid) {
                    project.tasks[i].predecessors.append(l)
                }
            }

            // Resources and assignments
            let resources = readResources()
            for (uid, name) in resources.sorted(by: { $0.key < $1.key }) where uid != 0 && !name.isEmpty {
                project.resources.append(ProjectResource(uid: uid, name: name))
            }
            for (taskUID, resourceUID) in readAssignments() {
                guard resources[resourceUID] != nil, let i = project.index(ofUID: taskUID),
                      !project.tasks[i].resourceUIDs.contains(resourceUID),
                      project.resources.contains(where: { $0.uid == resourceUID }) else { continue }
                project.tasks[i].resourceUIDs.append(resourceUID)
            }
            return project
        }

        func lagDays(_ raw: Int, _ unitsCode: Int) -> Int {
            let units = unitsCode & 0x1F
            if [19, 20, 51, 52].contains(units) { return 0 }                  // percentage lags aren't supported
            let minutes = Double(raw) / 10.0
            let elapsed = [4, 6, 8, 10, 12].contains(units)
            return Int((minutes / Double(elapsed ? 1440 : minutesPerDay)).rounded())
        }

        // MARK: Low-level blocks

        /// Item table (`FixedMeta`) plus the data it points into (`FixedData`).
        struct FixedBlock {
            var meta: [[UInt8]] = []
            var data: [[UInt8]?] = []
            var count: Int { meta.count }

            init(meta m: [UInt8], data d: [UInt8], itemSize: Int?, sizes: [Int] = [], otherCount: Int = 0, maxExpected: Int = 0) {
                guard m.u32(0) == 0xFADFADBA, m.count >= 16 else { return }
                let itemCount = m.i32(8)
                let avail = m.count - 16
                var size = itemSize ?? (sizes.first ?? 1)
                if itemSize == nil {
                    var distance = Int.min
                    for s in sizes where avail % s == 0 {
                        if avail / s == otherCount { size = s; break }
                        let dist = itemCount * s - avail
                        if dist <= 0 && dist > distance { size = s; distance = dist }
                    }
                }
                guard size > 0 else { return }
                let n = avail / size
                for i in 0..<n { meta.append(m.slice(16 + i * size, size)) }
                data = [[UInt8]?](repeating: nil, count: n)
                for i in 0..<n {
                    let off = meta[i].i32(4)
                    if off < 0 || off > d.count { continue }
                    var itemLength = (i + 1 == n) ? d.count - off : meta[i + 1].i32(4) - off
                    let available = d.count - off
                    if itemLength < 0 || itemLength > available {
                        itemLength = maxExpected == 0 ? available : Swift.min(maxExpected, available)
                    }
                    if maxExpected != 0 && itemLength > maxExpected { itemLength = maxExpected }
                    if itemLength > 0 { data[i] = d.slice(off, itemLength) }
                }
            }
        }

        /// Variable-length values keyed by (unique id, field type).
        struct VarBlock {
            var table: [Int: [Int: Int]] = [:]
            var data: [UInt8] = []

            init(meta m: [UInt8], data d: [UInt8]) {
                data = d
                let n = m.i32(8)
                var o = 24
                for _ in 0..<Swift.max(n, 0) {
                    guard o + 12 <= m.count else { break }
                    table[m.i32(o), default: [:]][m.u16(o + 8)] = m.i32(o + 4)
                    o += 12
                }
            }

            func bytes(_ uid: Int, _ type: Int) -> [UInt8]? {
                guard let off = table[uid]?[type], off >= 0, off + 4 <= data.count else { return nil }
                let size = data.i32(off)
                guard size >= 0, off + 4 + size <= data.count else { return nil }
                return data.slice(off + 4, size)
            }

            func string(_ uid: Int, _ type: Int) -> String? { bytes(uid, type)?.utf16String() }
        }

        /// Field map stored in the file's properties: field id → (block, offset) of fixed-size fields.
        static func parseFieldMap(_ b: [UInt8]) -> [Int: (block: Int, offset: Int)] {
            var out: [Int: (block: Int, offset: Int)] = [:]
            var block = 0, last = 0, o = 0
            while o + 28 <= b.count {
                let off = b.u16(o + 4)
                let key = Int(b.u32(o + 12) & 0xFFFF)
                let category = b.u16(o + 20)
                if category != 0x0B && category != 0x64 && off != 65535 {
                    if off < last { block += 1 }
                    last = off
                    out[key] = (block, off)
                }
                o += 28
            }
            return out
        }

        /// Time stamps are (6-second ticks, days since 1983-12-31). Only the date is used.
        static func day(from b: [UInt8], at o: Int) -> Day? {
            guard o >= 0, o + 4 <= b.count else { return nil }
            let days = b.u16(o + 2)
            if days <= 1 || days == 65535 { return nil }
            var ticks = b.u16(o)
            if ticks == 65535 { ticks = 0 }
            if days < 100 && (ticks * 6) % 60 != 0 { return nil }
            return Day(year: 1983, month: 12, day: 31).adding(days + (ticks * 6) / 86400)
        }

        // MARK: Tasks

        struct RawTask {
            var uid = 0, id = 0, level = 0, percent = 0, constraintType = 0
            var name = ""
            var milestone = false, manual = false
            var constraintDate: Day?, scheduledStart: Day?, start: Day?
            var scheduledDuration: Int?, manualDuration: Int?
        }

        func readTasks() -> [RawTask] {
            let d = "TBkndTask"
            guard let fixedMeta = stream(d, "FixedMeta"), let fixedData = stream(d, "FixedData"),
                  let varMeta = stream(d, "VarMeta"), let varData = stream(d, "Var2Data"),
                  let fixed2Meta = stream(d, "Fixed2Meta"), let fixed2Data = stream(d, "Fixed2Data") else { return [] }
            let vars = VarBlock(meta: varMeta, data: varData)
            let f1 = FixedBlock(meta: fixedMeta, data: fixedData, itemSize: 47)
            let f2 = FixedBlock(meta: fixed2Meta, data: fixed2Data, itemSize: nil, sizes: [92, 93, 94, 95, 96], otherCount: f1.count)

            let mapData = props[131092] ?? props[50331668] ?? []
            var fmap = Container.parseFieldMap(mapData)
            if fmap.isEmpty { fmap = Container.defaultTaskFieldMap }
            let uidOffset = fmap[86]?.offset ?? 0
            let maxSize = fmap.values.filter { $0.block == 0 }.map { $0.offset + 4 }.max() ?? 0

            // Which fixed item holds each task (later duplicates win; deleted items are skipped).
            var taskMap: [Int: Int?] = [:]
            var loop = f1.count - 1
            while loop > 2 {
                defer { loop -= 1 }
                guard let data = f1.data[loop], loop < f2.count, f2.data[loop] != nil else { continue }
                let flags = f1.meta[loop].i32(0)
                if flags & 2 != 0 {
                    let uid = data.u16(0)
                    if taskMap[uid] == nil { taskMap[uid] = .some(nil) }
                } else if data.count == 16 {
                    let uid = data.i32(0)
                    if taskMap[uid] == nil { taskMap[uid] = .some(loop) }
                } else if maxSize != 0 && (data.count * 100) / maxSize <= 75 {
                    continue
                } else {
                    let uid = data.i32(uidOffset)
                    if taskMap[uid] == nil || vars.table[uid] != nil {
                        if taskMap[uid] == nil || (flags & 4) == 0 { taskMap[uid] = .some(loop) }
                    }
                }
            }

            let metaVersionBit = version <= 14 ? (byte: 8, mask: 0x20) : (byte: 10, mask: 0x02)
            let manualMask = version <= 14 ? 0x08 : 0x80

            var out: [RawTask] = []
            for uid in taskMap.keys.sorted() {
                guard let slot = taskMap[uid], let idx = slot, let data = f1.data[idx], data.count != 16 else { continue }
                let data2 = idx < f2.count ? (f2.data[idx] ?? []) : []
                let meta = f1.meta[idx]
                let meta2 = idx < f2.count ? f2.meta[idx] : []
                let blocks = [data, data2]

                func field(_ key: Int, _ size: Int) -> (block: [UInt8], offset: Int)? {
                    guard let loc = fmap[key], loc.block < blocks.count else { return nil }
                    let b = blocks[loc.block]
                    return loc.offset + size <= b.count ? (b, loc.offset) : nil
                }
                func int32(_ key: Int) -> Int? { field(key, 4).map { $0.block.i32($0.offset) } }
                func int16(_ key: Int) -> Int? { field(key, 2).map { $0.block.u16($0.offset) } }
                func date(_ key: Int) -> Day? { field(key, 4).flatMap { Container.day(from: $0.block, at: $0.offset) } }

                var t = RawTask()
                t.uid = uid
                t.id = int32(23) ?? 0
                t.name = vars.string(uid, 14) ?? ""
                t.level = int16(249) ?? 0
                t.milestone = meta.count > metaVersionBit.byte && Int(meta[metaVersionBit.byte]) & metaVersionBit.mask != 0
                t.manual = meta2.count > 8 && Int(meta2[8]) & manualMask != 0
                t.percent = int16(32) ?? 0
                t.constraintType = int16(17) ?? 0
                t.constraintDate = date(18)
                t.scheduledDuration = int32(29)
                t.scheduledStart = date(35)
                t.start = date(1283)
                t.manualDuration = int32(1288)

                // The same task ID can appear twice; the copy without variable data is a phantom.
                if let dup = out.firstIndex(where: { $0.id == t.id }) {
                    if vars.table[uid] == nil { continue }
                    if out[dup].name.isEmpty { out.remove(at: dup) }
                }
                out.append(t)
            }
            return out
        }

        /// Offsets used by Project 2010 when a file carries no field map.
        static let defaultTaskFieldMap: [Int: (block: Int, offset: Int)] = [
            86: (0, 0), 23: (0, 4), 249: (0, 40), 29: (0, 42), 17: (0, 56), 18: (0, 80), 32: (0, 90),
            35: (0, 64), 36: (0, 68), 1283: (1, 50), 1284: (1, 54), 1288: (1, 58),
        ]

        // MARK: Links

        struct RawRelation { var pred = 0, succ = 0, type = 1, duration = 0, units = 7 }

        func readRelations() -> [RawRelation] {
            guard let meta = stream("TBkndCons", "FixedMeta"), let data = stream("TBkndCons", "FixedData"), meta.count >= 16 else { return [] }
            let newer = version > 14
            let durationOffset = newer ? 14 : 16
            let unitsOffset = newer ? 18 : 14
            var out: [RawRelation] = []
            for i in 0..<((meta.count - 16) / 10) {
                let m = meta.slice(16 + i * 10, 10)
                if m.u16(0) != 0 { continue }
                let off = m.i32(4)
                guard off >= 0, off + 14 <= data.count else { continue }
                let rec = data.slice(off, 20)
                guard rec.count >= 14 else { continue }
                let pred = rec.i32(4), succ = rec.i32(8)
                if pred == 0 || succ == 0 || pred == succ { continue }
                out.append(RawRelation(pred: pred, succ: succ, type: rec.u16(12),
                                       duration: rec.count >= durationOffset + 4 ? rec.i32(durationOffset) : 0,
                                       units: rec.count >= unitsOffset + 2 ? rec.u16(unitsOffset) : 7))
            }
            return out
        }

        // MARK: Resources and assignments

        func readResources() -> [Int: String] {
            let d = "TBkndRsc"
            guard let fm = stream(d, "FixedMeta"), let fd = stream(d, "FixedData"),
                  let vm = stream(d, "VarMeta"), let vd = stream(d, "Var2Data") else { return [:] }
            let vars = VarBlock(meta: vm, data: vd)
            let fixed = FixedBlock(meta: fm, data: fd, itemSize: 37)
            let rmap = Container.parseFieldMap(props[131093] ?? props[50331669] ?? [])
            let uidOffset = rmap[27]?.offset ?? 0
            var present = Set<Int>()
            for i in 0..<fixed.count {
                if let data = fixed.data[i], data.count >= uidOffset + 2 { present.insert(data.u16(uidOffset)) }
            }
            var out: [Int: String] = [:]
            for uid in vars.table.keys where present.contains(uid) { out[uid] = vars.string(uid, 1) ?? "" }
            return out
        }

        func readAssignments() -> [(Int, Int)] {
            let d = "TBkndAssn"
            guard let fm = stream(d, "FixedMeta"), let fd = stream(d, "FixedData"),
                  let vm = stream(d, "VarMeta"), let vd = stream(d, "Var2Data"), fm.count >= 16 else { return [] }
            let vars = VarBlock(meta: vm, data: vd)
            let amap = Container.parseFieldMap(props[131095] ?? props[50331671] ?? [])
            let idOffset = amap[0]?.offset ?? 0, taskOffset = amap[1]?.offset ?? 4, resourceOffset = amap[2]?.offset ?? 8
            var out: [(Int, Int)] = []
            for i in 0..<((fm.count - 16) / 34) {
                let m = fm.slice(16 + i * 34, 34)
                guard m.count > 0, m[0] == 0 else { continue }
                let off = m.i32(4)
                guard off >= 0, off < fd.count else { continue }
                let rec = fd.slice(off, 110)
                guard rec.count >= Swift.max(idOffset, taskOffset, resourceOffset) + 4 else { continue }
                if vars.table[rec.i32(idOffset)] == nil { continue }
                out.append((rec.i32(taskOffset), rec.i32(resourceOffset)))
            }
            return out
        }

        // MARK: Working calendar

        func readWorkWeek() -> WorkWeek {
            let d = "TBkndCal"
            let defaultWeek = [false, true, true, true, true, true, false]
            guard let fm = stream(d, "FixedMeta"), let fd = stream(d, "FixedData"),
                  let vm = stream(d, "VarMeta"), let vd = stream(d, "Var2Data") else { return .monFri }
            let vars = VarBlock(meta: vm, data: vd)
            let fixed = FixedBlock(meta: fm, data: fd, itemSize: 10, maxExpected: 12)
            let newer = version > 14
            let idOffset = newer ? 8 : 0, baseOffset = newer ? 0 : 4

            struct Cal { var base: Int; var name: String?; var data: [UInt8]? }
            var cals: [Int: Cal] = [:]
            for i in 0..<fixed.count {
                guard let item = fixed.data[i], item.count >= 8 else { continue }
                var o = 0
                while o + 12 <= item.count {
                    let cid = item.i32(o + idOffset), base = item.i32(o + baseOffset)
                    if cid > 0 && cals[cid] == nil {
                        cals[cid] = Cal(base: base, name: vars.string(cid, 1), data: vars.bytes(cid, 8))
                    }
                    o += 12
                }
            }

            /// For each weekday (Sunday first): true/false, or nil meaning "inherit".
            func dayFlags(_ data: [UInt8]?, _ fallback: [Bool], isBase: Bool) -> [Bool?] {
                (0..<7).map { idx -> Bool? in
                    let o = 60 * idx
                    let flag = data == nil ? 1 : data!.u16(o)
                    if flag == 1 { return isBase ? fallback[idx] : nil }
                    return data!.u16(o + 2) > 0
                }
            }

            var base = defaultWeek
            if let hours = props[37753736] { base = dayFlags(hours, defaultWeek, isBase: true).enumerated().map { $0.element ?? defaultWeek[$0.offset] } }

            func resolve(_ cid: Int, _ depth: Int) -> [Bool] {
                guard let c = cals[cid] else { return base }
                let isBase = c.base <= 0 || c.base == cid
                var flags = dayFlags(c.data, base, isBase: isBase)
                if !isBase && depth < 5 && cals[c.base] != nil {
                    let inherited = resolve(c.base, depth + 1)
                    flags = flags.enumerated().map { $0.element ?? inherited[$0.offset] }
                }
                return flags.enumerated().map { $0.element ?? base[$0.offset] }
            }

            let defaultName = props[37748750].map { $0.utf16String() }
            guard let target = cals.first(where: { $0.value.name == defaultName && defaultName != nil })?.key else {
                return WorkWeek(days: base.enumerated().filter { $0.element }.map { $0.offset })
            }
            let week = resolve(target, 0)
            return WorkWeek(days: week.enumerated().filter { $0.element }.map { $0.offset })
        }
    }
}
