import XCTest
@testable import ProjectCore

final class MPPTests: XCTestCase {
    func testRejectsNonOLEData() {
        XCTAssertFalse(MPP.isMPP(Data("<Project/>".utf8)))
        XCTAssertThrowsError(try MPP.read(Data("not a project".utf8)))
    }

    func testRejectsOLEWithoutProjectStreams() {
        // Valid OLE signature but nothing behind it.
        var bytes = [UInt8](repeating: 0, count: 1024)
        bytes.replaceSubrange(0..<8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        XCTAssertTrue(MPP.isMPP(Data(bytes)))
        XCTAssertThrowsError(try MPP.read(Data(bytes)))
    }

    func testByteHelpers() {
        let b: [UInt8] = [0x34, 0x12, 0xFF, 0xFF, 0xFF, 0xFF]
        XCTAssertEqual(b.u16(0), 0x1234)
        XCTAssertEqual(b.i32(2), -1)
        XCTAssertEqual(b.u16(5), 0)                      // out of range → 0
        XCTAssertEqual([0x41, 0x00, 0x42, 0x00, 0x00, 0x00, 0x43, 0x00].utf16String(), "AB")
    }

    /// Point GANTT_MPP_SAMPLE at a real .mpp (saved by Project 2010 or newer) to exercise the reader:
    ///   GANTT_MPP_SAMPLE=/path/OGP_Gantt_Chart.mpp swift test --filter MPPTests
    /// Expected values below come from the reference MPXJ reader for that particular file.
    func testRealFileIfProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["GANTT_MPP_SAMPLE"] else {
            throw XCTSkip("Set GANTT_MPP_SAMPLE to a .mpp file to run this test")
        }
        let p = try MPP.read(try Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(p.tasks.isEmpty)
        XCTAssertTrue(p.tasks.allSatisfy { !$0.name.isEmpty || $0.durationDays >= 0 })
        XCTAssertEqual(p.tasks.first?.outlineLevel, 1)
        // The schedule must compute without loops and cover every task.
        XCTAssertEqual(p.computeSchedule().byUID.count, p.tasks.count)
        // Round-trips through Project XML.
        let again = try MSPDI.read(MSPDI.write(p))
        XCTAssertEqual(again.tasks.map(\.name), p.tasks.map(\.name))
        XCTAssertEqual(again.workWeek, p.workWeek)

        if path.contains("OGP_Gantt_Chart") {
            XCTAssertEqual(p.tasks.count, 69)
            XCTAssertEqual(p.workWeek, .everyDay)
            XCTAssertEqual(p.tasks.indices.filter { !p.isSummary(at: $0) && p.tasks[$0].durationDays == 0 }.count, 12)
            XCTAssertEqual(p.resources.count, 15)
            XCTAssertEqual(p.tasks[0].outlineLevel, 1)
            XCTAssertEqual(p.startDate.iso, "2026-10-23")
        }
    }
}
