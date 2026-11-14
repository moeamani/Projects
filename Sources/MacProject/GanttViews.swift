import SwiftUI
import AppKit
import ProjectCore

private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

struct TimelineGeometry {
    let origin: Day
    let totalDays: Int
    let dayWidth: CGFloat

    var width: CGFloat { CGFloat(totalDays) * dayWidth }
    func x(_ day: Day) -> CGFloat { CGFloat(day.ordinal - origin.ordinal) * dayWidth }

    init(project: ProjectData, result: ScheduleResult, zoom: Zoom) {
        let first = result.byUID.values.map(\.start).min() ?? project.startDate
        let start = min(first, project.startDate)
        let mondayOffset = (start.weekday + 6) % 7
        origin = start.adding(-(7 + mondayOffset))
        let last = result.finish.adding(35)
        totalDays = max(last.ordinal - origin.ordinal + 1, 90)
        dayWidth = zoom.dayWidth
    }
}

struct DepLine {
    var fromX: CGFloat
    var fromRow: Int
    var toX: CGFloat
    var toRow: Int
    var arrivesAtEnd: Bool
}

struct TimelineHeader: View {
    let geo: TimelineGeometry
    let zoom: Zoom

    var body: some View {
        Canvas { ctx, size in
            let half = size.height / 2
            let line = GraphicsContext.Shading.color(.gray.opacity(0.35))
            func label(_ s: String, x: CGFloat, y: CGFloat, anchor: UnitPoint = .leading) {
                ctx.draw(Text(s).font(.system(size: 10)).foregroundColor(.secondary),
                         at: CGPoint(x: x, y: y), anchor: anchor)
            }
            func tick(x: CGFloat, from: CGFloat, to: CGFloat) {
                var p = Path(); p.move(to: CGPoint(x: x, y: from)); p.addLine(to: CGPoint(x: x, y: to))
                ctx.stroke(p, with: line, lineWidth: 0.5)
            }
            var rule = Path(); rule.move(to: CGPoint(x: 0, y: half)); rule.addLine(to: CGPoint(x: size.width, y: half))
            ctx.stroke(rule, with: line, lineWidth: 0.5)

            for i in 0..<geo.totalDays {
                let day = geo.origin.adding(i)
                let v = day.ymd
                let x = CGFloat(i) * geo.dayWidth
                // Top tier
                if zoom == .months {
                    if v.month == 1 || i == 0 { tick(x: x, from: 0, to: half); label("\(v.year)", x: x + 4, y: half / 2) }
                } else if v.day == 1 || i == 0 {
                    tick(x: x, from: 0, to: half)
                    label("\(monthNames[v.month - 1]) \(v.year)", x: x + 4, y: half / 2)
                }
                // Bottom tier
                switch zoom {
                case .days:
                    tick(x: x, from: half, to: size.height)
                    label("\(v.day)", x: x + geo.dayWidth / 2, y: half + half / 2, anchor: .center)
                case .weeks:
                    if day.weekday == 1 {
                        tick(x: x, from: half, to: size.height)
                        label("\(v.day)", x: x + 3, y: half + half / 2)
                    }
                case .months:
                    if v.day == 1 {
                        tick(x: x, from: half, to: size.height)
                        label(monthNames[v.month - 1], x: x + 3, y: half + half / 2)
                    }
                }
            }
        }
        .frame(width: geo.width, height: Metrics.headerH)
    }
}

struct GanttBackground: View {
    let geo: TimelineGeometry
    let rowCount: Int
    let selectedRows: Set<Int>
    let workWeek: WorkWeek
    let deps: [DepLine]
    let today: Day

    var body: some View {
        Canvas { ctx, size in
            let rh = Metrics.rowH
            // Selected rows
            for r in selectedRows {
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(r) * rh, width: size.width, height: rh)),
                         with: .color(Color.accentColor.opacity(0.12)))
            }
            // Weekends
            for i in 0..<geo.totalDays where !workWeek.isWorking(geo.origin.adding(i)) {
                ctx.fill(Path(CGRect(x: CGFloat(i) * geo.dayWidth, y: 0, width: geo.dayWidth, height: size.height)),
                         with: .color(Color.primary.opacity(0.045)))
            }
            // Row lines
            for r in 0...rowCount {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: CGFloat(r) * rh)); p.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * rh))
                ctx.stroke(p, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.5)
            }
            // Today
            let tx = geo.x(today) + geo.dayWidth / 2
            var tp = Path(); tp.move(to: CGPoint(x: tx, y: 0)); tp.addLine(to: CGPoint(x: tx, y: size.height))
            ctx.stroke(tp, with: .color(.orange.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Dependency arrows
            let arrowColor = GraphicsContext.Shading.color(Color.secondary)
            for d in deps {
                let fy = CGFloat(d.fromRow) * rh + rh / 2
                let ty = CGFloat(d.toRow) * rh + rh / 2
                var pts: [CGPoint] = [CGPoint(x: d.fromX, y: fy)]
                if d.arrivesAtEnd {
                    let x = max(d.fromX, d.toX) + 6
                    pts += [CGPoint(x: x, y: fy), CGPoint(x: x, y: ty), CGPoint(x: d.toX, y: ty)]
                } else if d.toX >= d.fromX + 12 {
                    pts += [CGPoint(x: d.fromX + 6, y: fy), CGPoint(x: d.fromX + 6, y: ty), CGPoint(x: d.toX, y: ty)]
                } else {
                    let midY = fy + (ty > fy ? rh / 2 : -rh / 2)
                    pts += [CGPoint(x: d.fromX + 6, y: fy), CGPoint(x: d.fromX + 6, y: midY),
                            CGPoint(x: d.toX - 6, y: midY), CGPoint(x: d.toX - 6, y: ty), CGPoint(x: d.toX, y: ty)]
                }
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: arrowColor, lineWidth: 1)
                let dir: CGFloat = d.arrivesAtEnd ? -1 : 1
                var head = Path()
                head.move(to: CGPoint(x: d.toX, y: ty))
                head.addLine(to: CGPoint(x: d.toX - 5 * dir, y: ty - 3))
                head.addLine(to: CGPoint(x: d.toX - 5 * dir, y: ty + 3))
                head.closeSubpath()
                ctx.fill(head, with: arrowColor)
            }
        }
        .frame(width: geo.width, height: CGFloat(rowCount) * Metrics.rowH)
    }
}

struct GanttBars: View {
    let rows: [Row]
    let geo: TimelineGeometry
    let onSelect: (Int) -> Void
    let onMove: (Int, Day) -> Void
    let onResize: (Int, Day) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                BarView(row: pair.element, geo: geo,
                        onSelect: { onSelect(pair.element.id) },
                        onMove: { onMove(pair.element.id, $0) },
                        onResize: { onResize(pair.element.id, $0) })
                    .offset(x: 0, y: CGFloat(pair.offset) * Metrics.rowH)
            }
        }
        .frame(width: geo.width, height: CGFloat(rows.count) * Metrics.rowH, alignment: .topLeading)
    }
}

struct BarView: View {
    let row: Row
    let geo: TimelineGeometry
    let onSelect: () -> Void
    let onMove: (Day) -> Void
    let onResize: (Day) -> Void

    @State private var dragX: CGFloat = 0
    @State private var resizeX: CGFloat = 0

    private var s: TaskSchedule { row.schedule }
    private var fullWidth: CGFloat { CGFloat(s.finish.ordinal - s.start.ordinal + 1) * geo.dayWidth }
    private var color: Color { s.isCritical ? .red : .blue }

    var body: some View {
        Group {
            if s.isSummary { summaryBar } else if row.task.durationDays == 0 { milestone } else { taskBar }
        }
        .frame(width: fullWidth, height: Metrics.rowH)
        .offset(x: geo.x(s.start))
        .help("\(row.task.name)\n\(s.start.iso) → \(s.finish.iso)" + (s.isSummary ? "" : "\nSlack: \(s.slackDays)d"))
    }

    private var summaryBar: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.primary.opacity(0.75))
            .frame(height: 6)
            .onTapGesture(perform: onSelect)
    }

    private var milestone: some View {
        Rectangle()
            .fill(color)
            .frame(width: 13, height: 13)
            .rotationEffect(.degrees(45))
            .frame(width: fullWidth, height: Metrics.rowH, alignment: .center)
            .offset(x: dragX)
            .gesture(moveGesture)
            .onTapGesture(perform: onSelect)
    }

    private var taskBar: some View {
        let width = max(geo.dayWidth * 0.6, fullWidth + resizeX)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.28))
            RoundedRectangle(cornerRadius: 3).fill(color)
                .frame(width: width * CGFloat(s.percentComplete) / 100)
        }
        .frame(width: width, height: 15)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.clear)
                .frame(width: 7)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(resizeGesture)
        }
        .frame(width: fullWidth, height: Metrics.rowH, alignment: .leading)
        .offset(x: dragX)
        .gesture(moveGesture)
        .onTapGesture(perform: onSelect)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { dragX = $0.translation.width }
            .onEnded { v in
                let days = Int((v.translation.width / geo.dayWidth).rounded())
                dragX = 0
                if days != 0 { onMove(s.start.adding(days)) }
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { resizeX = $0.translation.width }
            .onEnded { v in
                let days = Int((v.translation.width / geo.dayWidth).rounded())
                resizeX = 0
                if days != 0 { onResize(s.finish.adding(days)) }
            }
    }
}
