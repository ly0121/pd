import BeadCore
import Foundation
import SwiftData
import Testing
@testable import BeadPersistence

@Suite("BeadProjectRepository")
struct BeadProjectRepositoryTests {
    static func makeRepository() throws -> BeadProjectRepository {
        let schema = Schema([BeadProject.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return BeadProjectRepository(context: ModelContext(container))
    }

    static let palette = [
        MardColor(code: "F1", hex: "FD957B"),
        MardColor(code: "C5", hex: "01ACEB"),
    ]

    @Test("createProject persists a project with encoded grid and a generated thumbnail")
    func createProjectPersistsEncodedGridAndThumbnail() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 2, rows: 1, colors: [Self.palette[0], Self.palette[1]])
        let now = Date(timeIntervalSince1970: 1000)

        let project = try repository.createProject(name: "Cat", originalImageData: Data([0xFF]), grid: grid, now: now)

        #expect(project.name == "Cat")
        #expect(project.gridCodes == "F1,C5")
        #expect(project.thumbnailData != nil)
        #expect(project.createdAt == now)
        #expect(project.modifiedAt == now)
    }

    @Test("fetchAllSortedByModifiedAtDescending returns newest-first")
    func fetchAllReturnsNewestFirst() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 1, rows: 1, colors: [Self.palette[0]])

        try repository.createProject(name: "Old", originalImageData: Data(), grid: grid, now: Date(timeIntervalSince1970: 0))
        try repository.createProject(name: "New", originalImageData: Data(), grid: grid, now: Date(timeIntervalSince1970: 500))

        let all = try repository.fetchAllSortedByModifiedAtDescending()

        #expect(all.map(\.name) == ["New", "Old"])
    }

    @Test("decodeGrid reconstructs the same BeadGrid that was originally created")
    func decodeGridReconstructsOriginal() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 2, rows: 1, colors: [Self.palette[0], Self.palette[1]])
        let project = try repository.createProject(name: "Cat", originalImageData: Data(), grid: grid, now: Date())

        let decoded = try repository.decodeGrid(for: project, palette: Self.palette)

        #expect(decoded == grid)
    }

    @Test("updateGrid overwrites gridCodes, dimensions, thumbnail, and modifiedAt")
    func updateGridOverwritesState() throws {
        let repository = try Self.makeRepository()
        let original = BeadGrid(columns: 2, rows: 1, colors: [Self.palette[0], Self.palette[1]])
        let project = try repository.createProject(
            name: "Cat", originalImageData: Data(), grid: original, now: Date(timeIntervalSince1970: 0)
        )
        let originalThumbnail = project.thumbnailData

        let updated = BeadGrid(columns: 1, rows: 2, colors: [Self.palette[1], Self.palette[0]])
        try repository.updateGrid(for: project, grid: updated, now: Date(timeIntervalSince1970: 999))

        #expect(project.gridCodes == "C5,F1")
        #expect(project.columns == 1)
        #expect(project.rows == 2)
        #expect(project.modifiedAt == Date(timeIntervalSince1970: 999))
        #expect(project.thumbnailData != originalThumbnail)
    }

    @Test("delete removes the project from subsequent fetches")
    func deleteRemovesProject() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 1, rows: 1, colors: [Self.palette[0]])
        let project = try repository.createProject(name: "Gone", originalImageData: Data(), grid: grid, now: Date())

        try repository.delete(project)

        let all = try repository.fetchAllSortedByModifiedAtDescending()
        #expect(all.isEmpty)
    }
}
