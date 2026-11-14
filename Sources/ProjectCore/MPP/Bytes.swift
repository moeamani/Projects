import Foundation

extension Array where Element == UInt8 {
    /// Little-endian unsigned 16-bit value; 0 when out of range.
    func u16(_ o: Int) -> Int {
        guard o >= 0, o + 2 <= count else { return 0 }
        return Int(self[o]) | (Int(self[o + 1]) << 8)
    }

    /// Little-endian signed 32-bit value; 0 when out of range.
    func i32(_ o: Int) -> Int {
        guard o >= 0, o + 4 <= count else { return 0 }
        let v = UInt32(self[o]) | (UInt32(self[o + 1]) << 8) | (UInt32(self[o + 2]) << 16) | (UInt32(self[o + 3]) << 24)
        return Int(Int32(bitPattern: v))
    }

    func u32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= count else { return 0 }
        return UInt32(self[o]) | (UInt32(self[o + 1]) << 8) | (UInt32(self[o + 2]) << 16) | (UInt32(self[o + 3]) << 24)
    }

    /// Bounds-safe slice copy.
    func slice(_ from: Int, _ length: Int) -> [UInt8] {
        guard from >= 0, length > 0, from < count else { return [] }
        return Array(self[from..<Swift.min(from + length, count)])
    }

    /// UTF-16LE string up to the first NUL.
    func utf16String() -> String {
        var units: [UInt16] = []
        var i = 0
        while i + 1 < count {
            let u = UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
            if u == 0 { break }
            units.append(u)
            i += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}
