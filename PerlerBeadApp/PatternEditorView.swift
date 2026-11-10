import BeadCore
import BeadPersistence
import Photos
import SwiftData
import SwiftUI

enum EditorTool {
    case paint, erase, eyedropper
}

struct PatternEditorView: View {
    let project: BeadProject
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var ownedPalette: OwnedPaletteModel

    @State private var grid: BeadGrid?
    @State private var history = GridEditHistory()
    @State private var historyRevision = 0
    @State private var selectedTool: EditorTool = .paint
    @State private var selectedColor: MardColor?
    @State private var highlightedColorCode: String?
    @State private var eraseColor = MardColor(code: "H2", hex: "FEFFFF")
    @State private var loadError: String?
    @State private var saveResultMessage: String?
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("图纸画布")
                    .accessibilityValue("\(grid.columns)×\(grid.rows)")
                    .accessibilityIdentifier("patternGridCanvas")
                    .disabled(isRegenerating)
                    .allowsHitTesting(!isRegenerating)

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
        .background(AppTheme.editorBackground.ignoresSafeArea())
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") { saveToPhotoLibrary() }
                    .disabled(grid == nil || isRegenerating)
                    .accessibilityIdentifier("exportButton")
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
                    ownedPalette.refresh()
                    let palette = ownedPalette.colors
                    guard !palette.isEmpty else {
                        saveResultMessage = "我的拼豆颜色库为空，请先在「我的颜色」添加颜色"
                        return
                    }
                    regenerate(columns: size, palette: palette)
                }
            }
            .accessibilityIdentifier("confirmRegenerateButton")
            Button("取消", role: .cancel) { pendingRegenerateSize = nil }
        } message: {
            Text("当前手动上色的内容将被替换，且无法撤销。")
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { saveResultMessage != nil },
                set: { if !$0 { saveResultMessage = nil } }
            ),
            presenting: saveResultMessage
        ) { _ in
            Button("好") { saveResultMessage = nil }
        } message: { message in
            Text(message)
        }
        .task {
            loadGrid()
        }
        .onDisappear {
            if !isRegenerating, let grid { saver?.saveImmediately(grid) }
        }
    }

    /// Renders the current grid to a shareable image and saves it directly to the photo library
    /// with no confirmation prompt or preview screen — the user explicitly tapped "保存", so
    /// there's nothing left to confirm. Only surfaces UI when something goes wrong (permission
    /// denied, write failure); silent success matches the system Photos app's own save-from-share
    /// behavior.
    private func saveToPhotoLibrary() {
        guard let grid else { return }
        let image = PatternExportRenderer.render(grid)
        let hasTransparentCells = grid.colors.contains(.empty)
        let pngURL: URL?
        if hasTransparentCells {
            guard let data = image.pngData() else {
                saveResultMessage = "无法生成透明图片，请稍后重试"
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            do {
                try data.write(to: url, options: .atomic)
                pngURL = url
            } catch {
                saveResultMessage = "无法准备透明图片：\(error.localizedDescription)"
                return
            }
        } else {
            pngURL = nil
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges({
                    if let pngURL {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, fileURL: pngURL, options: nil)
                    } else {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }) { success, error in
                    if let pngURL { try? FileManager.default.removeItem(at: pngURL) }
                    if !success {
                        Task { @MainActor in
                            saveResultMessage = error?.localizedDescription ?? "无法保存图片，请稍后重试"
                        }
                    }
                }
            default:
                if let pngURL { try? FileManager.default.removeItem(at: pngURL) }
                Task { @MainActor in
                    saveResultMessage = "没有相册访问权限，请在系统设置中开启"
                }
            }
        }
    }

    private func loadGrid() {
        let repository = BeadProjectRepository(context: modelContext)
        saver = DebouncedGridSaver(repository: repository, project: project)
        regenerateSize = project.columns
        do {
            grid = try repository.decodeGrid(for: project)
        } catch {
            loadError = "图纸数据读取失败：\(error.localizedDescription)"
        }
    }

    /// Re-runs the full generation pipeline against the project's saved original photo at a new
    /// grid size, replacing the current grid (including any manual painting) once it completes.
    /// The caller is responsible for confirming with the user first, since this is destructive.
    private func regenerate(columns: Int, palette: [MardColor]) {
        guard let decodedImage = UIImage(data: project.originalImageData) else {
            saveResultMessage = "原图读取失败，图纸没有被修改"
            return
        }
        let sourceImage = NewProjectFlowModel.normalizedForGeneration(decodedImage)
        guard let grid else { return }
        do {
            try BeadProjectRepository(context: modelContext).updateGrid(for: project, grid: grid, now: Date())
        } catch {
            modelContext.rollback()
            saveResultMessage = "当前图纸保存失败，未开始重新生成：\(error.localizedDescription)"
            return
        }
        saver?.cancelPendingSave()
        isRegenerating = true

        Task { @MainActor in
            // The CPU-heavy generation work is offloaded to a detached task, which must not
            // capture `project`/`modelContext` (SwiftData types aren't Sendable) — so this
            // closure only takes and returns plain values, and all SwiftData access happens
            // back on the MainActor below once it returns.
            let newGrid = await Task.detached(priority: .userInitiated) { () -> BeadGrid? in
                // Hold only UI-test runs long enough to inspect the locked editor deterministically.
                if ProcessInfo.processInfo.arguments.contains("-UITestHoldEditorRegeneration") {
                    try? await Task.sleep(for: .seconds(8))
                }
                guard let downsampled = NewProjectFlowModel.downsample(sourceImage, targetColumns: columns),
                      let cgImage = downsampled.cgImage
                else { return nil }
                let options = PatternGenerationOptions(columns: columns, rows: columns, palette: palette)
                return PatternGenerator.generate(
                    cgImage: cgImage,
                    importanceProvider: VisionSaliencyImportanceMapProvider(),
                    options: options,
                    sourceAlphaImage: sourceImage.cgImage
                )
            }.value

            guard let newGrid else {
                isRegenerating = false
                saveResultMessage = "重新生成失败，图纸没有被修改"
                return
            }
            let repository = BeadProjectRepository(context: modelContext)
            do {
                try repository.updateGrid(for: project, grid: newGrid, now: Date())
                self.grid = newGrid
                history = GridEditHistory()
                historyRevision += 1
            } catch {
                modelContext.rollback()
                saveResultMessage = "重新生成保存失败，图纸没有被替换：\(error.localizedDescription)"
            }
            isRegenerating = false
        }
    }

    private func handleCellInteraction(col: Int, row: Int, isStrokeStart: Bool) {
        guard !isRegenerating, var currentGrid = grid else { return }

        switch selectedTool {
        case .paint:
            guard let selectedColor else { return }
            if isStrokeStart {
                history.recordBeforeEdit(currentGrid)
                historyRevision += 1
            }
            currentGrid.setColor(selectedColor, col: col, row: row)
            grid = currentGrid
            saver?.scheduleSave(currentGrid)
        case .erase:
            if isStrokeStart {
                history.recordBeforeEdit(currentGrid)
                historyRevision += 1
            }
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
                        guard !isRegenerating else { return }
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
                    .disabled(isRegenerating)
                    .accessibilityIdentifier("patternColorButton")
                }
            }
            .padding()
        }
        .background(AppTheme.editorPalette)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                showingSizePicker = true
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .disabled(grid == nil || isRegenerating)
            .accessibilityLabel("调整图纸大小")
            .accessibilityIdentifier("regenerateButton")
            toolButton(.paint, systemImage: "paintbrush.fill", label: "画笔")
            toolButton(.erase, systemImage: "eraser.fill", label: "橡皮擦")
            toolButton(.eyedropper, systemImage: "eyedropper", label: "吸管")
            Button {
                guard let current = grid, !isRegenerating else { return }
                history.recordBeforeEdit(current)
                historyRevision += 1
                let mirrored = current.mirroredHorizontally()
                grid = mirrored
                saver?.scheduleSave(mirrored)
            } label: {
                Image(systemName: "arrow.left.and.right")
            }
            .disabled(grid == nil || isRegenerating)
            .accessibilityLabel("左右镜像图纸")
            .accessibilityIdentifier("mirrorButton")
            Spacer(minLength: 0)
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(isRegenerating || !canUndo)
            .accessibilityLabel("撤销")
            .accessibilityIdentifier("undoButton")
            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(isRegenerating || !canRedo)
            .accessibilityLabel("重做")
            .accessibilityIdentifier("redoButton")
        }
        .foregroundStyle(AppTheme.textPrimary)
        .font(.system(size: 19))
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(AppTheme.editorToolbar)
    }

    private func toolButton(_ tool: EditorTool, systemImage: String, label: String) -> some View {
        Button {
            guard !isRegenerating else { return }
            selectedTool = tool
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(selectedTool == tool ? AppTheme.textPrimary : AppTheme.textPrimary.opacity(0.75))
                .padding(5)
                .background(selectedTool == tool ? AppTheme.coral.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(isRegenerating)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedTool == tool ? [.isSelected] : [])
    }

    private var canUndo: Bool {
        _ = historyRevision
        return history.canUndo
    }

    private var canRedo: Bool {
        _ = historyRevision
        return history.canRedo
    }

    private func undo() {
        guard !isRegenerating, let currentGrid = grid, let previous = history.undo(current: currentGrid) else { return }
        grid = previous
        historyRevision += 1
        saver?.scheduleSave(previous)
    }

    private func redo() {
        guard !isRegenerating, let currentGrid = grid, let next = history.redo(current: currentGrid) else { return }
        grid = next
        historyRevision += 1
        saver?.scheduleSave(next)
    }
}
