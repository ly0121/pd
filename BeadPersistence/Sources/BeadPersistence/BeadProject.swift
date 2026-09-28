import BeadCore
import Foundation
import SwiftData

@Model
public final class BeadProject {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var originalImageData: Data
    public var columns: Int
    public var rows: Int
    /// Serialized grid: one MARD color code per cell, row-major, joined by "," (e.g. "A1,A1,H7,...").
    /// Stored as a flat string rather than a relationship because MardColor is a lightweight
    /// value type, not a persisted model — see BeadGridCoding for the encode/decode logic.
    public var gridCodes: String
    public var thumbnailData: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        originalImageData: Data,
        columns: Int,
        rows: Int,
        gridCodes: String,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.originalImageData = originalImageData
        self.columns = columns
        self.rows = rows
        self.gridCodes = gridCodes
        self.thumbnailData = thumbnailData
    }
}
