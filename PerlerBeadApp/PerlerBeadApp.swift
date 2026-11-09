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
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}

private struct RootTabView: View {
    @StateObject private var ownedPalette = OwnedPaletteModel()

    var body: some View {
        TabView {
            ProjectListView()
                .tabItem { Label("图纸", systemImage: "square.grid.3x3") }
            OwnedPaletteView()
                .tabItem { Label("我的颜色", systemImage: "paintpalette") }
        }
        .environmentObject(ownedPalette)
    }
}
