import XCTest
@testable import ProjectCore

final class DayTests: XCTestCase {
    func testCivilConversions() {
        XCTAssertEqual(Day(ordinal: 0).ymd.year, 1970)
        XCTAssertEqual(Day(ordinal: 0).weekday, 4)                       // Thursday
        let d = Day(year: 2026, month: 11, day: 16)
        XCTAssertEqual(d.ymd.year, 2026); XCTAssertEqual(d.ymd.month, 11); XCTAssertEqual(d.ymd.day, 16)
        XCTAssertEqual(d.weekday, 1)                                     // Monday
        XCTAssertEqual(d.iso, "2026-11-16")
        XCTAssertEqual(Day(iso: "2026-11-16T08:00:00"), d)
        XCTAssertEqual(Day(year: 2024, month: 2, day: 29).adding(1).iso, "2024-03-01")
    }

    func testWorkIndexSkipsWeekends() {
        let fri = Day(year: 2026, month: 11, day: 20)
        let sat = Day(year: 2026, month: 11, day: 21)
        let mon = Day(year: 2026, month: 11, day: 23)
        XCTAssertEqual(sat.nextWorkingDay(), mon)
        XCTAssertEqual(Day(workIndex: fri.workIndex() + 1), mon)
        XCTAssertEqual(Day(workIndex: mon.workIndex()), mon)
        XCTAssertEqual(sat.workIndex(), mon.workIndex())
        // Before 1970 too
        let old = Day(year: 1969, month: 12, day: 29)                    // Monday
        XCTAssertEqual(Day(workIndex: old.workIndex()), old)
    }

    func testCustomWorkWeeks() {
        // Saturday–Wednesday week (common in the Middle East): Thu/Fri off.
        let week = WorkWeek(days: [6, 0, 1, 2, 3])
        let wed = Day(year: 2026, month: 11, day: 18)
        let thu = Day(year: 2026, month: 11, day: 19)
        let sat = Day(year: 2026, month: 11, day: 21)
        XCTAssertEqual(thu.nextWorkingDay(week), sat)
        XCTAssertEqual(Day(workIndex: wed.workIndex(week) + 1, week), sat)
        for offset in -20...20 {
            let d = Day(year: 2026, month: 11, day: 18).adding(offset).nextWorkingDay(week)
            XCTAssertEqual(Day(workIndex: d.workIndex(week), week), d)
        }
        // Seven-day week: every day is consecutive.
        let all = WorkWeek.everyDay
        XCTAssertEqual(Day(workIndex: wed.workIndex(all) + 3, all), wed.adding(3))
    }
}

final class ScheduleTests: XCTestCase {
    let monday = Day(year: 2026, month: 11, day: 16)

    func project(_ tasks: [ProjectTask]) -> ProjectData {
        ProjectData(name: "T", startDate: monday, tasks: tasks, resources: [])
    }

    func testFinishToStartSkipsWeekend() {
        let p = project([
            ProjectTask(uid: 1, name: "A", durationDays: 3),
            ProjectTask(uid: 2, name: "B", durationDays: 2, predecessors: [Link(predecessorUID: 1)]),
            ProjectTask(uid: 3, name: "C", durationDays: 1, predecessors: [Link(predecessorUID: 2)]),
        ])
        let r = p.computeSchedule().byUID
        XCTAssertEqual(r[1]!.start.iso, "2026-11-16"); XCTAssertEqual(r[1]!.finish.iso, "2026-11-18")
        XCTAssertEqual(r[2]!.start.iso, "2026-11-19"); XCTAssertEqual(r[2]!.finish.iso, "2026-11-20")
        XCTAssertEqual(r[3]!.start.iso, "2026-11-23")
    }

    func testStartToStartWithLagAndMilestone() {
        let p = project([
            ProjectTask(uid: 1, name: "A", durationDays: 5),
            ProjectTask(uid: 2, name: "B", durationDays: 2, predecessors: [Link(predecessorUID: 1, type: .ss, lagDays: 1)]),
            ProjectTask(uid: 3, name: "M", durationDays: 0, predecessors: [Link(predecessorUID: 2)]),
        ])
        let r = p.computeSchedule().byUID
        XCTAssertEqual(r[2]!.start.iso, "2026-11-17")
        XCTAssertEqual(r[3]!.start.iso, "2026-11-19")                    // right after B (17,18)
        XCTAssertEqual(r[3]!.finish, r[3]!.start)
    }

    func testFinishToFinish() {
        let p = project([
            ProjectTask(uid: 1, name: "A", durationDays: 5),
            ProjectTask(uid: 2, name: "B", durationDays: 2, predecessors: [Link(predecessorUID: 1, type: .ff)]),
        ])
        XCTAssertEqual(p.computeSchedule().byUID[2]!.finish.iso, "2026-11-20")
    }

    func testStartConstraint() {
        var t = ProjectTask(uid: 1, name: "A", durationDays: 1)
        t.startNoEarlierThan = Day(year: 2026, month: 11, day: 21)       // Saturday → Monday
        XCTAssertEqual(project([t]).computeSchedule().byUID[1]!.start.iso, "2026-11-23")
    }

    func testSummaryRollupAndCriticalPath() {
        let p = project([
            ProjectTask(uid: 1, name: "S", outlineLevel: 1),
            ProjectTask(uid: 2, name: "A", outlineLevel: 2, durationDays: 3, percentComplete: 100),
            ProjectTask(uid: 3, name: "B", outlineLevel: 2, durationDays: 1),
            ProjectTask(uid: 4, name: "C", outlineLevel: 2, durationDays: 1, predecessors: [Link(predecessorUID: 2)]),
        ])
        let r = p.computeSchedule().byUID
        XCTAssertTrue(r[1]!.isSummary)
        XCTAssertEqual(r[1]!.start.iso, "2026-11-16")
        XCTAssertEqual(r[1]!.finish.iso, "2026-11-19")
        XCTAssertEqual(r[1]!.durationDays, 4)
        XCTAssertEqual(r[1]!.percentComplete, 60)                        // (3*100)/5
        XCTAssertTrue(r[2]!.isCritical); XCTAssertTrue(r[4]!.isCritical)
        XCTAssertFalse(r[3]!.isCritical)
        XCTAssertEqual(r[3]!.slackDays, 3)
    }

    func testCycleIsRejectedAndScheduleSurvivesOne() {
        var p = project([
            ProjectTask(uid: 1, name: "A"),
            ProjectTask(uid: 2, name: "B", predecessors: [Link(predecessorUID: 1)]),
        ])
        XCTAssertThrowsError(try p.parsePredecessors("2", forTaskAt: 0))
        XCTAssertFalse(p.addLink(fromUID: 2, toUID: 1))
        // A hand-edited file with a loop must not hang or crash.
        p.tasks[0].predecessors = [Link(predecessorUID: 2)]
        let r = p.computeSchedule().byUID
        XCTAssertTrue(r[1]!.inCycle)
    }
}

final class EditingTests: XCTestCase {
    func testPredecessorTextRoundTrip() throws {
        var p = ProjectData(name: "T", startDate: Day(year: 2026, month: 11, day: 16))
        for i in 1...4 { p.tasks.append(ProjectTask(uid: i, name: "T\(i)")) }
        let links = try p.parsePredecessors("1, 2SS+2d, 3FF-1d", forTaskAt: 3)
        XCTAssertEqual(links, [Link(predecessorUID: 1), Link(predecessorUID: 2, type: .ss, lagDays: 2),
                               Link(predecessorUID: 3, type: .ff, lagDays: -1)])
        p.tasks[3].predecessors = links
        XCTAssertEqual(p.predecessorText(forTaskAt: 3), "1, 2SS+2d, 3FF-1d")
        XCTAssertThrowsError(try p.parsePredecessors("9", forTaskAt: 3))
        XCTAssertThrowsError(try p.parsePredecessors("4", forTaskAt: 3))
        XCTAssertThrowsError(try p.parsePredecessors("abc", forTaskAt: 3))
        XCTAssertEqual(try p.parsePredecessors("", forTaskAt: 3), [])
    }

    func testIndentOutdentMoveDelete() {
        var p = ProjectData(name: "T")
        for i in 1...4 { p.addTask(after: p.tasks.isEmpty ? nil : p.tasks.count - 1, name: "T\(i)") }
        p.indent([2])
        XCTAssertEqual(p.tasks.map(\.outlineLevel), [1, 2, 1, 1])
        XCTAssertTrue(p.isSummary(at: 0))
        p.indent([2])                                                    // already a child of T1: can't go deeper
        XCTAssertEqual(p.tasks.map(\.outlineLevel), [1, 2, 1, 1])
        p.indent([3])
        XCTAssertEqual(p.tasks.map(\.outlineLevel), [1, 2, 2, 1])
        p.outdent([2, 3])
        XCTAssertEqual(p.tasks.map(\.outlineLevel), [1, 1, 1, 1])
        p.moveDown([1]); XCTAssertEqual(p.tasks.map(\.uid), [2, 1, 3, 4])
        p.moveUp([4]);   XCTAssertEqual(p.tasks.map(\.uid), [2, 1, 4, 3])
        p.addLink(fromUID: 1, toUID: 3)
        p.deleteTasks([1])
        XCTAssertEqual(p.tasks.map(\.uid), [2, 4, 3])
        XCTAssertTrue(p.tasks.allSatisfy { $0.predecessors.isEmpty })
    }

    func testDeletingSummaryDeletesChildren() {
        var p = ProjectData(name: "T", tasks: [
            ProjectTask(uid: 1, name: "S"), ProjectTask(uid: 2, name: "a", outlineLevel: 2),
            ProjectTask(uid: 3, name: "b", outlineLevel: 2), ProjectTask(uid: 4, name: "z"),
        ])
        p.deleteTasks([1])
        XCTAssertEqual(p.tasks.map(\.uid), [4])
    }

    func testInputParsing() {
        XCTAssertEqual(ProjectData.parseDuration("5"), 5)
        XCTAssertEqual(ProjectData.parseDuration("5d"), 5)
        XCTAssertEqual(ProjectData.parseDuration("2w"), 10)
        XCTAssertEqual(ProjectData.parseDuration("0"), 0)
        XCTAssertNil(ProjectData.parseDuration("abc"))
        XCTAssertNil(ProjectData.parseDuration("-1"))
        XCTAssertEqual(ProjectData.parsePercent("150%"), 100)
    }
}

final class MSPDITests: XCTestCase {
    func testRoundTrip() throws {
        var p = ProjectData.sample()
        p.name = "Fish & <Chips> \"quoted\""
        p.tasks[5].startNoEarlierThan = Day(year: 2027, month: 1, day: 11)
        p.tasks[5].predecessors.append(Link(predecessorUID: 2, type: .ss, lagDays: 2))
        let data = MSPDI.write(p)
        let q = try MSPDI.read(data)
        XCTAssertEqual(q.tasks, p.tasks)
        XCTAssertEqual(q.resources, p.resources)
        XCTAssertEqual(q.name, p.name)
        XCTAssertEqual(q.startDate, p.startDate)
        XCTAssertEqual(q.computeSchedule().byUID, p.computeSchedule().byUID)
    }

    func testWrittenXMLHasMicrosoftNamespaceAndExpectedFields() throws {
        let xml = String(decoding: MSPDI.write(ProjectData.sample()), as: UTF8.self)
        XCTAssertTrue(xml.contains("xmlns=\"http://schemas.microsoft.com/project\""))
        XCTAssertTrue(xml.contains("<Duration>PT24H0M0S</Duration>"))    // 3 days
        XCTAssertTrue(xml.contains("<PredecessorUID>2</PredecessorUID>"))
        XCTAssertTrue(xml.contains("<OutlineLevel>2</OutlineLevel>"))
    }

    func testReadsFileFromMicrosoftProject() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Project xmlns="http://schemas.microsoft.com/project">
          <Name>Plan.xml</Name><StartDate>2026-11-16T08:00:00</StartDate><MinutesPerDay>480</MinutesPerDay>
          <Tasks>
            <Task><UID>0</UID><ID>0</ID><Name>Plan</Name><OutlineLevel>0</OutlineLevel><Summary>1</Summary></Task>
            <Task><UID>1</UID><ID>1</ID><Name>Design</Name><OutlineLevel>1</OutlineLevel><Duration>PT16H0M0S</Duration><PercentComplete>25</PercentComplete></Task>
            <Task><UID>2</UID><ID>2</ID><Name>Build</Name><OutlineLevel>1</OutlineLevel><Duration>PT40H0M0S</Duration>
              <PredecessorLink><PredecessorUID>1</PredecessorUID><Type>3</Type><LinkLag>4800</LinkLag><LagFormat>7</LagFormat></PredecessorLink></Task>
            <Task><UID>3</UID><ID>3</ID><Name>Done</Name><OutlineLevel>1</OutlineLevel><Milestone>1</Milestone><Duration>PT0H0M0S</Duration></Task>
            <Task><UID>4</UID><IsNull>1</IsNull><OutlineLevel>1</OutlineLevel></Task>
          </Tasks>
          <Resources><Resource><UID>0</UID><ID>0</ID></Resource><Resource><UID>1</UID><ID>1</ID><Name>Pat</Name></Resource></Resources>
          <Assignments><Assignment><UID>1</UID><TaskUID>2</TaskUID><ResourceUID>1</ResourceUID></Assignment></Assignments>
        </Project>
        """
        let p = try MSPDI.read(Data(xml.utf8))
        XCTAssertEqual(p.name, "Plan")
        XCTAssertEqual(p.tasks.map(\.name), ["Design", "Build", "Done"])
        XCTAssertEqual(p.tasks.map(\.durationDays), [2, 5, 0])
        XCTAssertEqual(p.tasks[0].percentComplete, 25)
        XCTAssertEqual(p.tasks[1].predecessors, [Link(predecessorUID: 1, type: .ss, lagDays: 1)])
        XCTAssertEqual(p.resources, [ProjectResource(uid: 1, name: "Pat")])
        XCTAssertEqual(p.tasks[1].resourceUIDs, [1])
    }

    /// Shaped like a real file saved by Project: 24-hour 7-day calendar, 1440-minute days,
    /// manually scheduled tasks with fixed dates and no links, and non-Latin (Persian) names.
    func testSevenDayManuallyScheduledProject() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Project xmlns="http://schemas.microsoft.com/project">
          <Name>project.xml</Name><StartDate>2026-10-23T00:00:00</StartDate>
          <CalendarUID>3</CalendarUID><MinutesPerDay>1440</MinutesPerDay>
          <Calendars>
            <Calendar><UID>1</UID><Name>Standard</Name><IsBaseCalendar>1</IsBaseCalendar><BaseCalendarUID>-1</BaseCalendarUID>
              <WeekDays><WeekDay><DayType>1</DayType><DayWorking>0</DayWorking></WeekDay></WeekDays></Calendar>
            <Calendar><UID>3</UID><Name>24 Hours</Name><IsBaseCalendar>1</IsBaseCalendar><BaseCalendarUID>-1</BaseCalendarUID>
              <WeekDays>
                <WeekDay><DayType>1</DayType><DayWorking>1</DayWorking></WeekDay>
                <WeekDay><DayType>2</DayType><DayWorking>1</DayWorking></WeekDay>
                <WeekDay><DayType>3</DayType><DayWorking>1</DayWorking></WeekDay>
                <WeekDay><DayType>4</DayType><DayWorking>1</DayWorking></WeekDay>
                <WeekDay><DayType>5</DayType><DayWorking>1</DayWorking></WeekDay>
                <WeekDay><DayType>6</DayType><DayWorking>1</DayWorking></WeekDay>
                <WeekDay><DayType>7</DayType><DayWorking>1</DayWorking></WeekDay>
              </WeekDays></Calendar>
          </Calendars>
          <Tasks>
            <Task><UID>1</UID><ID>1</ID><Name>ارزشیابی هوشمند</Name><Manual>1</Manual><OutlineLevel>1</OutlineLevel>
              <Start>2026-10-23T00:00:00</Start><Duration>PT143H59M0S</Duration><Summary>1</Summary></Task>
            <Task><UID>2</UID><ID>2</ID><Name>تحقیقات</Name><Manual>1</Manual><OutlineLevel>2</OutlineLevel>
              <Start>2026-10-23T00:00:00</Start><Duration>PT95H59M0S</Duration><ConstraintType>0</ConstraintType></Task>
            <Task><UID>3</UID><ID>3</ID><Name>طراحی</Name><Manual>1</Manual><OutlineLevel>2</OutlineLevel>
              <Start>2026-10-27T00:00:00</Start><Duration>PT143H59M0S</Duration></Task>
            <Task><UID>4</UID><ID>4</ID><Name>پایان</Name><Manual>1</Manual><OutlineLevel>2</OutlineLevel><Milestone>1</Milestone>
              <Start>2026-11-02T23:59:00</Start><Duration>PT0H0M0S</Duration><ConstraintType>4</ConstraintType>
              <ConstraintDate>2026-11-02T23:59:00</ConstraintDate></Task>
          </Tasks>
        </Project>
        """
        let p = try MSPDI.read(Data(xml.utf8))
        XCTAssertEqual(p.workWeek, .everyDay)
        XCTAssertEqual(p.tasks.map(\.durationDays), [1, 4, 6, 0])        // summary rows are recomputed, not read
        let r = p.computeSchedule().byUID
        XCTAssertEqual(r[2]!.start.iso, "2026-10-23"); XCTAssertEqual(r[2]!.finish.iso, "2026-10-26")   // 4 calendar days
        XCTAssertEqual(r[3]!.start.iso, "2026-10-27"); XCTAssertEqual(r[3]!.finish.iso, "2026-11-01")   // 6 days, spans a weekend
        XCTAssertEqual(r[4]!.start.iso, "2026-11-02")
        XCTAssertEqual(r[1]!.start.iso, "2026-10-23"); XCTAssertEqual(r[1]!.finish.iso, "2026-11-01")
        XCTAssertEqual(p.tasks[1].name, "تحقیقات")
        // Saved back out, the 7-day calendar and the names survive.
        let again = try MSPDI.read(MSPDI.write(p))
        XCTAssertEqual(again.workWeek, .everyDay)
        XCTAssertEqual(again.tasks.map(\.name), p.tasks.map(\.name))
        XCTAssertEqual(again.computeSchedule().byUID, r)
    }

    func testRejectsNonProjectXML() {
        XCTAssertThrowsError(try MSPDI.read(Data("<html/>".utf8)))
        XCTAssertThrowsError(try MSPDI.read(Data("not xml".utf8)))
    }
}
