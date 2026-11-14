# MacProject

A native macOS project-planning app (Swift + SwiftUI) in the spirit of Microsoft Project:
task table, Gantt chart, dependencies, milestones, summary tasks, critical path and resources.

## Opening files in Windows

The app's file format **is Microsoft Project's XML format (MSPDI)**. Save in MacProject, then in
Project for Windows use **File ▸ Open** and pick the file (choose the "XML Format" filter if it's hidden).
Files saved from Project as **XML Format** open in MacProject the same way.

The binary `.mpp` format is proprietary and is not supported. In Project for Windows use
**File ▸ Save As ▸ XML Format** first.

## Build & run (on a Mac, macOS 14+, Xcode 15+ / Swift 5.9+)

```bash
./scripts/build_app.sh && open build/MacProject.app
```

or open `Package.swift` in Xcode and run the `MacProject` scheme. Unit tests: `swift test`.
Every push also builds and tests on GitHub Actions and uploads `MacProject.app` as an artifact.

## Using it

| Do this | How |
|---|---|
| Add task / milestone | toolbar `+` / ◇ (⌘↩ for a task) |
| Edit a cell | click it: name, duration (`5`, `5d`, `2w`, `0` = milestone), start, %, resources |
| Link tasks | type row numbers in **Predecessors** (`3`, `5SS`, `4FS+2d`), or select rows and press **Link** |
| Subtasks / summaries | **Indent** (⌘]) / **Outdent** (⌘[); click the chevron to collapse |
| Reschedule | drag a bar to move it (sets "start no earlier than" 📌); drag its right edge to change duration |
| Critical path | red bars have zero slack |
| Undo | ⌘Z works for every edit |

## How scheduling works

Mon–Fri, 8 h working days. Supports FS / SS / FF / SF links with lag, start-no-earlier-than
constraints, summary roll-up and critical-path (slack) calculation. Circular links are rejected.

## Limitations (v1)

- One fixed working calendar (no holidays or custom calendars); durations in whole days.
- No baselines, costs, resource leveling or work-hours per resource.
- Links to/from summary tasks are kept in the file but ignored for scheduling.
- Constraints other than "start no earlier than" (MSO, deadlines…) are not editable; "must start on" is imported as "no earlier than".
- Windows round-trip is verified by unit tests against the MSPDI structure, but has not yet been
  verified in Project itself — see below.
