import SwiftUI
import ProjectCore

struct ResourcesView: View {
    let project: ProjectData
    let onAdd: () -> Void
    let onRename: (Int, String) -> Bool
    let onDelete: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Resources").font(.headline)
                Spacer()
                Button { onAdd() } label: { Label("Add Resource", systemImage: "plus") }
            }
            .padding(12)
            Divider()
            if project.resources.isEmpty {
                Text("No resources yet. Add people or equipment, then assign them to tasks from the Tasks tab.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(project.resources) { r in
                        HStack {
                            Image(systemName: "person.fill").foregroundStyle(.secondary)
                            CommitField(value: r.name) { onRename(r.uid, $0) }
                            Spacer()
                            let count = project.tasks.filter { $0.resourceUIDs.contains(r.uid) }.count
                            Text("\(count) task\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
                            Button { onDelete(r.uid) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }
}
