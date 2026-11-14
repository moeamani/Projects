import Foundation

/// Minimal reader for OLE2 / Compound File Binary containers (the wrapper around .mpp files).
struct CompoundFile {
    private let bytes: [UInt8]
    private var sectorSize = 512
    private var miniSectorSize = 64
    private var miniCutoff = 4096
    private var fat: [UInt32] = []
    private var miniFat: [UInt32] = []
    private var miniStream: [UInt8] = []
    private var streams: [String: (start: Int, size: Int)] = [:]

    private static let endOfChain = 0xFFFFFFFA        // values at or above this are markers

    static func looksLikeOLE(_ data: Data) -> Bool {
        data.count >= 8 && Array(data.prefix(8)) == [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    }

    init?(_ data: Data) {
        guard CompoundFile.looksLikeOLE(data), data.count >= 512 else { return nil }
        bytes = [UInt8](data)
        let shift = bytes.u16(0x1E), miniShift = bytes.u16(0x20)
        guard (7...16).contains(shift), (1...12).contains(miniShift) else { return nil }
        sectorSize = 1 << shift
        miniSectorSize = 1 << miniShift
        let numFat = bytes.i32(0x2C)
        let dirStart = Int(bytes.u32(0x30))
        miniCutoff = bytes.i32(0x38)
        let miniFatStart = Int(bytes.u32(0x3C))
        let numMiniFat = bytes.i32(0x40)
        let difatStart = Int(bytes.u32(0x44))
        let numDifat = bytes.i32(0x48)

        // Sector numbers of the FAT sectors: 109 in the header, the rest chained through DIFAT sectors.
        var fatSectors: [Int] = []
        for i in 0..<109 { fatSectors.append(Int(bytes.u32(0x4C + i * 4))) }
        var sector = difatStart
        let perDifat = sectorSize / 4 - 1
        var guardCount = 0
        while sector < CompoundFile.endOfChain, guardCount < max(numDifat, 0) {
            let base = offset(of: sector)
            for i in 0..<perDifat { fatSectors.append(Int(bytes.u32(base + i * 4))) }
            sector = Int(bytes.u32(base + perDifat * 4))
            guardCount += 1
        }
        fatSectors = Array(fatSectors.filter { $0 < CompoundFile.endOfChain }.prefix(Swift.max(numFat, 0)))
        for s in fatSectors {
            let base = offset(of: s)
            guard base + sectorSize <= bytes.count else { continue }
            for i in 0..<(sectorSize / 4) { fat.append(bytes.u32(base + i * 4)) }
        }

        let dir = chain(start: dirStart)
        guard dir.count >= 128 else { return nil }
        var entries: [(name: String, type: Int, left: Int, right: Int, child: Int, start: Int, size: Int)] = []
        for i in 0..<(dir.count / 128) {
            let e = dir.slice(i * 128, 128)
            let nameLength = e.u16(64)
            let name = Array(e.prefix(Swift.max(Swift.min(nameLength - 2, 64), 0))).utf16String()
            entries.append((name, Int(e[66]), Int(e.u32(68)), Int(e.u32(72)), Int(e.u32(76)),
                            Int(e.u32(116)), Int(e.u32(120))))
        }
        let root = entries[0]
        miniStream = Array(chain(start: root.start).prefix(root.size))
        if numMiniFat > 0 {
            let raw = chain(start: miniFatStart)
            for i in 0..<(raw.count / 4) { miniFat.append(raw.u32(i * 4)) }
        }

        // Walk the directory tree (a red-black tree per storage), recording stream paths.
        var visited = Set<Int>()
        func walk(_ idx: Int, _ prefix: String) {
            guard idx != 0xFFFFFFFF, idx >= 0, idx < entries.count, visited.insert(idx).inserted else { return }
            let e = entries[idx]
            walk(e.left, prefix)
            if e.type == 2 {
                streams[prefix + e.name] = (e.start, e.size)
            } else if e.type == 1 {
                walk(e.child, prefix + e.name + "/")
            }
            walk(e.right, prefix)
        }
        walk(root.child, "")
    }

    /// Names of all streams, e.g. "   114/TBkndTask/FixedData".
    var streamNames: [String] { Array(streams.keys) }

    func read(_ path: String) -> [UInt8]? {
        guard let e = streams[path] else { return nil }
        if e.size < miniCutoff { return miniChain(start: e.start, size: e.size) }
        return Array(chain(start: e.start).prefix(e.size))
    }

    private func offset(of sector: Int) -> Int { (sector + 1) * sectorSize }

    private func chain(start: Int) -> [UInt8] {
        var out: [UInt8] = []
        var seen = Set<Int>()
        var s = start
        while s < CompoundFile.endOfChain, s < fat.count, seen.insert(s).inserted {
            let base = offset(of: s)
            guard base >= 0, base < bytes.count else { break }
            out.append(contentsOf: bytes[base..<Swift.min(base + sectorSize, bytes.count)])
            s = Int(fat[s])
        }
        return out
    }

    private func miniChain(start: Int, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        var seen = Set<Int>()
        var s = start
        while s < CompoundFile.endOfChain, s < miniFat.count, seen.insert(s).inserted {
            let base = s * miniSectorSize
            guard base < miniStream.count else { break }
            out.append(contentsOf: miniStream[base..<Swift.min(base + miniSectorSize, miniStream.count)])
            s = Int(miniFat[s])
        }
        return Array(out.prefix(size))
    }
}
