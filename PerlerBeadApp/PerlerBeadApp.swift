import BeadPersistence
import SwiftData
import SwiftUI

@main
struct PerlerBeadApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: BeadProject.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
        }
        .modelContainer(modelContainer)
    }
}
