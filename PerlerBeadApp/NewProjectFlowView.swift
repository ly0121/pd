import BeadCore
import BeadPersistence
import PhotosUI
import SwiftData
import SwiftUI

enum NewProjectStep {
    case pickImage
    case crop(UIImage)
    case pickGridSize(UIImage)
    case generating
    case failed(String)
}

enum PatternAspectMode: Hashable {
    case square
    case fitContent
}

@MainActor
final class NewProjectFlowModel: ObservableObject {
    @Published var step: NewProjectStep = .pickImage
    @Published var selectedGridSize: Int = 48
    @Published var photosPickerItem: PhotosPickerItem?
    /// The image before square cropping — kept alongside the cropped image so "适应内容" (fit
    /// content) generation can use the original aspect ratio instead of being locked to
    /// `ImageCropView`'s square crop frame.
    @Published var originalImage: UIImage?
    @Published var removeBackground = false
    @Published var aspectMode: PatternAspectMode = .square
    @Published var paletteSelection: PalettePreset = .mine

    private let modelContext: ModelContext
    var onProjectCreated: ((BeadProject) -> Void)?

    init(modelContext: ModelContext, initialImage: UIImage? = nil) {
        self.modelContext = modelContext
        if let initialImage {
            self.originalImage = initialImage
            self.step = .crop(initialImage)
        }
    }

    func loadPickedPhoto() async {
        guard let photosPickerItem else { return }
        guard let data = try? await photosPickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            step = .failed("无法读取所选图片")
            return
        }
        originalImage = image
        step = .crop(image)
    }

    func confirmCrop(_ croppedImage: UIImage) {
        step = .pickGridSize(croppedImage)
    }

    /// Generates a simple synthetic image in-process (a colored square on a contrasting
    /// background) so UI tests can exercise the full pipeline without depending on the real
    /// photo library or bundling a fixture image asset.
    func useSampleImageForTesting() {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.3, green: 0.55, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 50, y: 50, width: 100, height: 100))
        }
        originalImage = image
        step = .crop(image)
    }

    /// `croppedImage` is the square-cropped image from the crop step. Depending on `aspectMode`,
    /// generation may use it directly (`.square`) or fall back to `originalImage` (`.fitContent`)
    /// to preserve the source photo's real aspect ratio instead of the crop frame's square shape.
    func generate(from croppedImage: UIImage, columns: Int) {
        step = .generating

        let sourceImage = aspectMode == .square ? croppedImage : (originalImage ?? croppedImage)
        let (targetColumns, targetRows) = Self.dimensions(for: sourceImage, columns: columns, aspectMode: aspectMode)
        let palette = paletteSelection.colors
        let maskProvider: ForegroundMaskProvider = removeBackground ? VisionForegroundMaskProvider() : UniformForegroundMaskProvider()

        Task.detached(priority: .userInitiated) { [weak self] in
            // The algorithm pipeline (SLIC segmentation, contour detection, Vision saliency) all
            // scale with pixel count, but a bead grid only ever needs one color per cell — running
            // them against a multi-thousand-pixel photo straight from the camera wastes almost all
            // of that work. Downsampling first to a resolution just dense enough for good per-cell
            // averaging (a small multiple of the grid size) cuts generation time dramatically with
            // no visible quality loss in the final pattern.
            guard let downsampled = Self.downsample(sourceImage, targetColumns: max(targetColumns, targetRows)),
                  let cgImage = downsampled.cgImage
            else {
                await self?.fail("图片处理失败")
                return
            }
            let options = PatternGenerationOptions(columns: targetColumns, rows: targetRows, palette: palette)
            let grid = PatternGenerator.generate(
                cgImage: cgImage,
                importanceProvider: VisionSaliencyImportanceMapProvider(),
                options: options,
                foregroundMaskProvider: maskProvider
            )
            // Persist whichever image was actually used for generation (not necessarily the
            // square-cropped one) so a later "regenerate at a different size" reuses the same
            // source the user picked here.
            let imageData = sourceImage.pngData() ?? Data()
            await self?.finishGeneration(grid: grid, imageData: imageData)
        }
    }

    /// Resizes `image` so its longer side is about `pixelsPerCell` pixels per grid column/row
    /// (never upscaling), preserving aspect ratio. `pixelsPerCell` of 6 keeps enough detail for
    /// SLIC's per-cell color averaging to stay accurate while capping the pixel count the rest
    /// of the pipeline has to process.
    nonisolated static func downsample(_ image: UIImage, targetColumns: Int, pixelsPerCell: CGFloat = 6) -> UIImage? {
        let longerSide = max(image.size.width, image.size.height)
        let targetLongerSide = CGFloat(targetColumns) * pixelsPerCell
        guard longerSide > targetLongerSide else { return image }

        let scale = targetLongerSide / longerSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// For `.square`, the grid is always `columns` x `columns` (unchanged from the original
    /// behavior). For `.fitContent`, `columns` applies to the image's longer side, and the
    /// shorter side is scaled proportionally (minimum 1, so a very elongated image never
    /// collapses to a zero-size dimension).
    nonisolated static func dimensions(for image: UIImage, columns: Int, aspectMode: PatternAspectMode) -> (columns: Int, rows: Int) {
        guard aspectMode == .fitContent else { return (columns, columns) }
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return (columns, columns) }

        if width >= height {
            let rows = max(1, Int((Double(columns) * Double(height) / Double(width)).rounded()))
            return (columns, rows)
        } else {
            let cols = max(1, Int((Double(columns) * Double(width) / Double(height)).rounded()))
            return (cols, columns)
        }
    }

    @MainActor
    private func finishGeneration(grid: BeadGrid, imageData: Data) {
        let repository = BeadProjectRepository(context: modelContext)
        do {
            let project = try repository.createProject(
                name: "拼豆图纸 \(Date().formatted(date: .abbreviated, time: .shortened))",
                originalImageData: imageData,
                grid: grid,
                now: Date()
            )
            onProjectCreated?(project)
        } catch {
            step = .failed("保存失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func fail(_ message: String) {
        step = .failed(message)
    }
}

struct NewProjectFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var model: NewProjectFlowModelBox
    let initialImage: UIImage?
    let onProjectCreated: (BeadProject) -> Void

    init(initialImage: UIImage? = nil, onProjectCreated: @escaping (BeadProject) -> Void) {
        _model = StateObject(wrappedValue: NewProjectFlowModelBox())
        self.initialImage = initialImage
        self.onProjectCreated = onProjectCreated
    }

    var body: some View {
        content
            .onAppear {
                if model.instance == nil {
                    model.instance = NewProjectFlowModel(modelContext: modelContext, initialImage: initialImage)
                    model.instance?.onProjectCreated = onProjectCreated
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let flow = model.instance {
            NewProjectFlowContentView(model: flow)
        } else {
            ProgressView()
        }
    }
}

/// SwiftUI's @StateObject can't be initialized with a value that depends on @Environment
/// (modelContext isn't available until the view body evaluates), so this box defers creating
/// the real NewProjectFlowModel until onAppear while still giving SwiftUI a stable object
/// identity to observe from the very first render.
final class NewProjectFlowModelBox: ObservableObject {
    @Published var instance: NewProjectFlowModel?
}

private struct NewProjectFlowContentView: View {
    @ObservedObject var model: NewProjectFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaletteMaterialPicker = false

    var body: some View {
        Group {
            switch model.step {
            case .pickImage:
                pickImageView
            case .crop(let image):
                ImageCropView(
                    sourceImage: image,
                    onConfirm: { model.confirmCrop($0) },
                    onCancel: { model.step = .pickImage }
                )
            case .pickGridSize(let image):
                generationSettingsView(image: image)
            case .generating:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在生成图纸…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(spacing: 16) {
                    Text(message).foregroundStyle(.red)
                    Button("重试") { model.step = .pickImage }
                }
            }
        }
        .navigationTitle("新建图纸")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    /// Only reached when the flow wasn't handed an `initialImage` (UI test path, or "重试" after
    /// a generation failure) — the primary "+" -> system photo picker path now lives in
    /// `ProjectListView`, which opens this flow already past this step via `initialImage`.
    private var pickImageView: some View {
        VStack(spacing: 20) {
            PhotosPicker(selection: Binding(
                get: { model.photosPickerItem },
                set: { newValue in
                    model.photosPickerItem = newValue
                    Task { await model.loadPickedPhoto() }
                }
            ), matching: .images) {
                Text("从相册选择照片")
            }
            .buttonStyle(RoundedCardButtonStyle())
            .accessibilityIdentifier("pickPhotoButton")

            // UI tests can't reliably drive the system PHPickerViewController (it runs out of
            // process), so when launched with -UITestUseSampleImage this button substitutes a
            // bundled sample image for the real picker, letting tests exercise the rest of the
            // flow (crop -> grid size -> generate -> editor -> export) end to end.
            if ProcessInfo.processInfo.arguments.contains("-UITestUseSampleImage") {
                Button("使用测试图片") {
                    model.useSampleImageForTesting()
                }
                .buttonStyle(RoundedCardButtonStyle())
                .accessibilityIdentifier("useSampleImageButton")
            }
        }
        .padding()
    }

    /// The merged "生成设置" step: preview, background removal toggle, aspect ratio choice, grid
    /// size picker, and bead material (palette preset) row, all before the final generate button.
    private func generationSettingsView(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                previewImage(croppedImage: image)

                Toggle("去除背景", isOn: Binding(
                    get: { model.removeBackground },
                    set: { model.removeBackground = $0 }
                ))
                .padding(.horizontal)
                .accessibilityIdentifier("removeBackgroundToggle")

                VStack(alignment: .leading, spacing: 8) {
                    Text("图纸比例")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Picker("图纸比例", selection: Binding(
                        get: { model.aspectMode },
                        set: { model.aspectMode = $0 }
                    )) {
                        Text("正方形").tag(PatternAspectMode.square)
                        Text("适应内容").tag(PatternAspectMode.fitContent)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("aspectModePicker")

                GridSizePickerContent(selectedSize: Binding(
                    get: { model.selectedGridSize },
                    set: { model.selectedGridSize = $0 }
                ))

                paletteMaterialRow

                Button(generateButtonLabel) {
                    model.generate(from: image, columns: model.selectedGridSize)
                }
                .buttonStyle(RoundedCardButtonStyle())
                .accessibilityIdentifier("generatePatternButton")
                .padding()
            }
        }
        .sheet(isPresented: $showingPaletteMaterialPicker) {
            PaletteMaterialPickerSheet(selection: Binding(
                get: { model.paletteSelection },
                set: { model.paletteSelection = $0 }
            ))
        }
    }

    private func previewImage(croppedImage: UIImage) -> some View {
        let displayedImage = model.aspectMode == .square ? croppedImage : (model.originalImage ?? croppedImage)
        return Image(uiImage: displayedImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .padding(.horizontal)
    }

    private var paletteMaterialRow: some View {
        Button {
            showingPaletteMaterialPicker = true
        } label: {
            HStack {
                Text("拼豆材料")
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(model.paletteSelection.label)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            }
            .padding()
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        }
        .padding(.horizontal)
        .accessibilityIdentifier("paletteMaterialRow")
    }

    private var generateButtonLabel: String {
        model.aspectMode == .square
            ? "生成图纸（\(model.selectedGridSize)×\(model.selectedGridSize)）"
            : "生成图纸（长边\(model.selectedGridSize)格）"
    }
}
