# Gantt

A native macOS project-planning app (Swift + SwiftUI) in the spirit of Microsoft Project:
task table, Gantt chart, dependencies, milestones, summary tasks, critical path and resources.

## File formats

- **Native format: Microsoft Project XML (MSPDI).** Save in Gantt, then in Project for Windows use
  **File ▸ Open** and pick the file (choose the "XML Format" filter if it's hidden). Files saved from
  Project as **XML Format** open in Gantt too.
- **Opening `.mpp`:** Gantt reads native `.mpp` files saved by **Project 2010 or newer** (including
  2013, 2016, 2019 and 365). Tasks, outline, durations, manually-scheduled dates, links, resources,
  assignments and the working calendar are imported; everything else (baselines, costs, custom
  fields, views) is ignored. `.mpp` files are opened as a copy: use **File ▸ Save As** to save a
  Project XML file, which Project for Windows opens. Gantt never writes `.mpp`.
- Project 2007 or older `.mpp` files and password-protected files aren't supported; in Project use
  **File ▸ Save As ▸ XML Format** first.

The `.mpp` reader follows the layout documented by the open-source MPXJ project. It was checked
against MPXJ's own reader on 165 sample files (2,460 tasks): task names, outline levels,
durations, dates, links, resources, assignments and working weeks all agreed (one deliberately
corrupted sample excepted). Run your own file through it with
`GANTT_MPP_SAMPLE=/path/file.mpp swift test --filter MPPTests`.

## Build & run (on a Mac, macOS 14+, Xcode 15+ / Swift 5.9+)

```bash
./scripts/build_app.sh && open build/Gantt.app
```

or open `Package.swift` in Xcode and run the `Gantt` scheme. Unit tests: `swift test`.
Every push also builds and tests on GitHub Actions and uploads `Gantt.app` as an artifact.

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
- Saved XML follows the element order Project itself writes, but hasn't been opened in Project for
  Windows yet.
