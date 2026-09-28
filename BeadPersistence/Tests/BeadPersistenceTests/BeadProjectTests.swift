import BeadCore
import Foundation
import SwiftData
import Testing
@testable import BeadPersistence

@Suite("BeadProject")
struct BeadProjectTests {
    /// Creates a fresh in-memory ModelContainer per test so tests don't share persisted state.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([BeadProject.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("inserting and fetching a project round-trips all fields")
    func insertAndFetchRoundTrips() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let grid = BeadGrid(columns: 2, rows: 1, colors: [
            MardColor(code: "F1", hex: "FD957B"),
            MardColor(code: "C5", hex: "01ACEB"),
        ])
        let project = BeadProject(
            name: "Test Cat",
            createdAt: now,
            modifiedAt: now,
            originalImageData: Data([0x01, 0x02, 0x03]),
            columns: 2,
            rows: 1,
            gridCodes: BeadGridCoding.encode(grid)
        )
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BeadProject>())

        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Test Cat")
        #expect(fetched[0].columns == 2)
        #expect(fetched[0].rows == 1)
        #expect(fetched[0].gridCodes == "F1,C5")
        #expect(fetched[0].originalImageData == Data([0x01, 0x02, 0x03]))
    }

    @Test("updating a project's gridCodes persists the change")
    func updateProjectPersists() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let project = BeadProject(
            name: "Editable",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            originalImageData: Data(),
            columns: 1,
            rows: 1,
            gridCodes: "F1"
        )
        context.insert(project)
        try context.save()

        project.gridCodes = "C5"
        project.modifiedAt = Date(timeIntervalSince1970: 100)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BeadProject>())
        #expect(fetched.count == 1)
        #expect(fetched[0].gridCodes == "C5")
        #expect(fetched[0].modifiedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("deleting a project removes it from subsequent fetches")
    func deleteProjectRemovesIt() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let project = BeadProject(
            name: "ToDelete",
            createdAt: Date(), modifiedAt: Date(),
            originalImageData: Data(), columns: 1, rows: 1, gridCodes: "F1"
        )
        context.insert(project)
        try context.save()

        context.delete(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BeadProject>())
        #expect(fetched.isEmpty)
    }

    @Test("multiple projects can be fetched sorted by modifiedAt descending")
    func fetchSortedByModifiedAtDescending() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let older = BeadProject(
            name: "Older", createdAt: Date(timeIntervalSince1970: 0), modifiedAt: Date(timeIntervalSince1970: 0),
            originalImageData: Data(), columns: 1, rows: 1, gridCodes: "F1"
        )
        let newer = BeadProject(
            name: "Newer", createdAt: Date(timeIntervalSince1970: 100), modifiedAt: Date(timeIntervalSince1970: 200),
            originalImageData: Data(), columns: 1, rows: 1, gridCodes: "C5"
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        var descriptor = FetchDescriptor<BeadProject>()
        descriptor.sortBy = [SortDescriptor(\.modifiedAt, order: .reverse)]
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.name) == ["Newer", "Older"])
    }
}
