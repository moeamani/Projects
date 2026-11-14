import SwiftUI

@main
struct MacProjectApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ProjectDocument()) { file in
            ContentView(document: file.$document)
                .frame(minWidth: 1100, minHeight: 520)
        }
        .defaultSize(width: 1360, height: 780)
    }
}
