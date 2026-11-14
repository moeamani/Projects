import SwiftUI
import UniformTypeIdentifiers
import ProjectCore

/// A project file. Saved as Microsoft Project XML (MSPDI), which Project for Windows opens directly.
struct ProjectDocument: FileDocument {
    /// Microsoft Project's native binary format. Opened read-only; saving always writes Project XML.
    static let mppType = UTType(importedAs: "com.microsoft.project.mpp", conformingTo: .data)

    static var readableContentTypes: [UTType] { [.xml, mppType] }
    static var writableContentTypes: [UTType] { [.xml] }

    var project: ProjectData

    init(project: ProjectData = .sample()) { self.project = project }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            project = try (MPP.isMPP(data) ? MPP.read(data) : MSPDI.read(data))
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Never write XML into a file that is named .mpp: Project would refuse it.
        if configuration.contentType == ProjectDocument.mppType {
            throw CocoaError(.fileWriteUnsupportedScheme, userInfo: [
                NSLocalizedDescriptionKey: "Gantt can't write .mpp files. Use File ▸ Save As… and save as Project XML, which opens in Microsoft Project."])
        }
        return FileWrapper(regularFileWithContents: MSPDI.write(project))
    }
}
