import BeadCore
import Foundation
import SwiftData

/// Application-facing repository wrapping SwiftData CRUD + BeadGrid encode/decode + thumbnail
/// generation, so the UI layer never touches ModelContext, gridCodes strings, or
/// ThumbnailRenderer directly.
public struct BeadProjectRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func createProject(name: String, originalImageData: Data, grid: BeadGrid, now: Date) throws -> BeadProject {
        let project = BeadProject(
            name: name,
            createdAt: now,
            modifiedAt: now,
            originalImageData: originalImageData,
            columns: grid.columns,
            rows: grid.rows,
            gridCodes: BeadGridCoding.encode(grid),
            thumbnailData: ThumbnailRenderer.renderPNGData(grid)
        )
        context.insert(project)
        try context.save()
        return project
    }

    public func fetchAllSortedByModifiedAtDescending() throws -> [BeadProject] {
        var descriptor = FetchDescriptor<BeadProject>()
        descriptor.sortBy = [SortDescriptor(\.modifiedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }

    public func decodeGrid(for project: BeadProject, palette: [MardColor]) throws -> BeadGrid {
        try BeadGridCoding.decode(project.gridCodes, columns: project.columns, rows: project.rows, palette: palette)
    }

    public func updateGrid(for project: BeadProject, grid: BeadGrid, now: Date) throws {
        project.gridCodes = BeadGridCoding.encode(grid)
        project.columns = grid.columns
        project.rows = grid.rows
        project.thumbnailData = ThumbnailRenderer.renderPNGData(grid)
        project.modifiedAt = now
        try context.save()
    }

    public func delete(_ project: BeadProject) throws {
        context.delete(project)
        try context.save()
    }
}
