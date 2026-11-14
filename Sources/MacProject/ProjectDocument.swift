import SwiftUI
import UniformTypeIdentifiers
import ProjectCore

/// A project file. Saved as Microsoft Project XML (MSPDI), which Project for Windows opens directly.
struct ProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    static var writableContentTypes: [UTType] { [.xml] }

    var project: ProjectData

    init(project: ProjectData = .sample()) { self.project = project }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            project = try MSPDI.read(data)
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: MSPDI.write(project))
    }
}
