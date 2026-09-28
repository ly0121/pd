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

@MainActor
final class NewProjectFlowModel: ObservableObject {
    @Published var step: NewProjectStep = .pickImage
    @Published var selectedGridSize: Int = 48
    @Published var photosPickerItem: PhotosPickerItem?

    private let modelContext: ModelContext
    var onProjectCreated: ((BeadProject) -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadPickedPhoto() async {
        guard let photosPickerItem else { return }
        guard let data = try? await photosPickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            step = .failed("无法读取所选图片")
            return
        }
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
        step = .crop(image)
    }

    func generate(from image: UIImage, columns: Int) {
        step = .generating
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let cgImage = image.cgImage else {
                await self?.fail("图片处理失败")
                return
            }
            let options = PatternGenerationOptions(columns: columns, rows: columns)
            let grid = PatternGenerator.generate(
                cgImage: cgImage,
                importanceProvider: VisionSaliencyImportanceMapProvider(),
                options: options
            )
            let imageData = image.pngData() ?? Data()
            await self?.finishGeneration(grid: grid, imageData: imageData)
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
    let onProjectCreated: (BeadProject) -> Void

    init(onProjectCreated: @escaping (BeadProject) -> Void) {
        _model = StateObject(wrappedValue: NewProjectFlowModelBox())
        self.onProjectCreated = onProjectCreated
    }

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear {
            if model.instance == nil {
                model.instance = NewProjectFlowModel(modelContext: modelContext)
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
                gridSizeStepView(image: image)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

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

    private func gridSizeStepView(image: UIImage) -> some View {
        VStack {
            GridSizePickerContent(selectedSize: Binding(
                get: { model.selectedGridSize },
                set: { model.selectedGridSize = $0 }
            ))
            Button("生成图纸（\(model.selectedGridSize)×\(model.selectedGridSize)）") {
                model.generate(from: image, columns: model.selectedGridSize)
            }
            .buttonStyle(RoundedCardButtonStyle())
            .accessibilityIdentifier("generatePatternButton")
            .padding()
        }
    }
}
