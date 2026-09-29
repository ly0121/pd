import BeadCore
import BeadPersistence
import SwiftData
import SwiftUI

enum EditorTool {
    case paint, erase, eyedropper
}

struct PatternEditorView: View {
    let project: BeadProject
    @Environment(\.modelContext) private var modelContext

    @State private var grid: BeadGrid?
    @State private var history = GridEditHistory()
    @State private var selectedTool: EditorTool = .paint
    @State private var selectedColor: MardColor?
    @State private var highlightedColorCode: String?
    @State private var eraseColor = MardColor(code: "H2", hex: "FEFFFF")
    @State private var loadError: String?
    @State private var showingExport = false
    @State private var saver: DebouncedGridSaver?
    @State private var showingSizePicker = false
    @State private var regenerateSize: Int = 0
    @State private var pendingRegenerateSize: Int?
    @State private var isRegenerating = false

    var body: some View {
        VStack(spacing: 0) {
            if let grid {
                ZStack {
                    BeadGridCanvas(
                        grid: grid,
                        highlightedColorCode: highlightedColorCode,
                        onCellTouched: { col, row, isStrokeStart in
                            handleCellInteraction(col: col, row: row, isStrokeStart: isStrokeStart)
                        }
                    )
                    .background(Color.white)

                    if isRegenerating {
                        Color.black.opacity(0.15)
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("正在重新生成图纸…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                    }
                }

                colorPalette(for: grid)
                toolbar
            } else if let loadError {
                Text(loadError).foregroundStyle(.red).padding()
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("导出") { showingExport = true }
                    .disabled(grid == nil || isRegenerating)
                    .accessibilityIdentifier("exportButton")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSizePicker = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(grid == nil || isRegenerating)
                .accessibilityIdentifier("regenerateButton")
            }
        }
        .sheet(isPresented: $showingExport) {
            if let grid {
                ExportView(grid: grid, projectName: project.name)
            }
        }
        .sheet(isPresented: $showingSizePicker) {
            GridSizePickerSheet(selectedSize: $regenerateSize, onSelect: { pendingRegenerateSize = regenerateSize })
        }
        .confirmationDialog(
            "用 \(pendingRegenerateSize ?? regenerateSize)×\(pendingRegenerateSize ?? regenerateSize) 重新生成图纸？",
            isPresented: Binding(
                get: { pendingRegenerateSize != nil },
                set: { if !$0 { pendingRegenerateSize = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("重新生成", role: .destructive) {
                if let size = pendingRegenerateSize {
                    pendingRegenerateSize = nil
                    regenerate(columns: size)
                }
            }
            .accessibilityIdentifier("confirmRegenerateButton")
            Button("取消", role: .cancel) { pendingRegenerateSize = nil }
        } message: {
            Text("当前手动上色的内容将被替换，且无法撤销。")
        }
        .task {
            loadGrid()
        }
        .onDisappear {
            if let grid { saver?.saveImmediately(grid) }
        }
    }

    private func loadGrid() {
        let repository = BeadProjectRepository(context: modelContext)
        saver = DebouncedGridSaver(repository: repository, project: project)
        regenerateSize = project.columns
        do {
            grid = try repository.decodeGrid(for: project, palette: MardPalette.standard221)
        } catch {
            loadError = "图纸数据读取失败：\(error.localizedDescription)"
        }
    }

    /// Re-runs the full generation pipeline against the project's saved original photo at a new
    /// grid size, replacing the current grid (including any manual painting) once it completes.
    /// The caller is responsible for confirming with the user first, since this is destructive.
    private func regenerate(columns: Int) {
        guard let sourceImage = UIImage(data: project.originalImageData) else { return }
        isRegenerating = true

        Task { @MainActor in
            // The CPU-heavy generation work is offloaded to a detached task, which must not
            // capture `project`/`modelContext` (SwiftData types aren't Sendable) — so this
            // closure only takes and returns plain values, and all SwiftData access happens
            // back on the MainActor below once it returns.
            let newGrid = await Task.detached(priority: .userInitiated) { () -> BeadGrid? in
                guard let downsampled = NewProjectFlowModel.downsample(sourceImage, targetColumns: columns),
                      let cgImage = downsampled.cgImage
                else { return nil }
                let options = PatternGenerationOptions(columns: columns, rows: columns)
                return PatternGenerator.generate(
                    cgImage: cgImage,
                    importanceProvider: VisionSaliencyImportanceMapProvider(),
                    options: options
                )
            }.value

            guard let newGrid else {
                isRegenerating = false
                return
            }
            let repository = BeadProjectRepository(context: modelContext)
            try? repository.updateGrid(for: project, grid: newGrid, now: Date())
            grid = newGrid
            history = GridEditHistory()
            isRegenerating = false
        }
    }

    private func handleCellInteraction(col: Int, row: Int, isStrokeStart: Bool) {
        guard var currentGrid = grid else { return }

        switch selectedTool {
        case .paint:
            guard let selectedColor else { return }
            if isStrokeStart { history.recordBeforeEdit(currentGrid) }
            currentGrid.setColor(selectedColor, col: col, row: row)
            grid = currentGrid
            saver?.scheduleSave(currentGrid)
        case .erase:
            if isStrokeStart { history.recordBeforeEdit(currentGrid) }
            currentGrid.setColor(eraseColor, col: col, row: row)
            grid = currentGrid
            saver?.scheduleSave(currentGrid)
        case .eyedropper:
            guard isStrokeStart else { return }
            selectedColor = currentGrid.color(col: col, row: row)
            selectedTool = .paint
        }
    }

    private func colorPalette(for grid: BeadGrid) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ColorUsageCalculator.usages(for: grid)) { usage in
                    Button {
                        selectedColor = usage.color
                        selectedTool = .paint
                        highlightedColorCode = (highlightedColorCode == usage.color.code) ? nil : usage.color.code
                    } label: {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(Color(red: usage.color.red, green: usage.color.green, blue: usage.color.blue))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(selectedColor?.code == usage.color.code ? AppTheme.coral : .clear, lineWidth: 3)
                                )
                            Text(usage.color.code)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("\(usage.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.cardBackground)
    }

    private var toolbar: some View {
        HStack(spacing: 24) {
            toolButton(.paint, systemImage: "paintbrush.fill")
            toolButton(.erase, systemImage: "eraser.fill")
            toolButton(.eyedropper, systemImage: "eyedropper")
            Spacer()
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!history.canUndo)
            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!history.canRedo)
        }
        .font(.system(size: 20))
        .padding()
        .background(Color.white)
    }

    private func toolButton(_ tool: EditorTool, systemImage: String) -> some View {
        Button {
            selectedTool = tool
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(selectedTool == tool ? AppTheme.coral : AppTheme.textPrimary)
        }
    }

    private func undo() {
        guard let currentGrid = grid, let previous = history.undo(current: currentGrid) else { return }
        grid = previous
        saver?.scheduleSave(previous)
    }

    private func redo() {
        guard let currentGrid = grid, let next = history.redo(current: currentGrid) else { return }
        grid = next
        saver?.scheduleSave(next)
    }
}
