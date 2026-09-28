import BeadCore
import Foundation

/// Fixed-size undo/redo history over BeadGrid snapshots. Bounded at `maxDepth` entries to avoid
/// unbounded memory growth on a long editing session (each snapshot is O(columns*rows), and a
/// 200x200 grid edited hundreds of times would otherwise retain hundreds of full-size copies).
final class GridEditHistory {
    private var undoStack: [BeadGrid] = []
    private var redoStack: [BeadGrid] = []
    private let maxDepth: Int

    init(maxDepth: Int = 50) {
        self.maxDepth = maxDepth
    }

    func recordBeforeEdit(_ grid: BeadGrid) {
        undoStack.append(grid)
        if undoStack.count > maxDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo(current: BeadGrid) -> BeadGrid? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    func redo(current: BeadGrid) -> BeadGrid? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
