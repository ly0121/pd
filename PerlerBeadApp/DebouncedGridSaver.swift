import BeadCore
import BeadPersistence
import Foundation
import SwiftData

/// Debounces BeadGrid persistence so a drag-paint gesture (which can call `save`  once per pixel
/// moved over) collapses into a single SwiftData write shortly after the user stops interacting,
/// rather than saving on every intermediate cell change.
@MainActor
final class DebouncedGridSaver {
    private let repository: BeadProjectRepository
    private let project: BeadProject
    private let delaySeconds: Double
    private var pendingTask: Task<Void, Never>?

    init(repository: BeadProjectRepository, project: BeadProject, delaySeconds: Double = 0.6) {
        self.repository = repository
        self.project = project
        self.delaySeconds = delaySeconds
    }

    func scheduleSave(_ grid: BeadGrid) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try? repository.updateGrid(for: project, grid: grid, now: Date())
        }
    }

    /// Cancels any pending debounced save and writes immediately — used when the view is about
    /// to disappear, so an in-flight edit isn't lost to a debounce window that never fires.
    func saveImmediately(_ grid: BeadGrid) {
        pendingTask?.cancel()
        pendingTask = nil
        try? repository.updateGrid(for: project, grid: grid, now: Date())
    }
}
