# 拼豆图纸编辑器 + 导入导出 UI（PerlerBeadApp）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 iOS App target（`PerlerBeadApp`），把 Plan A（`BeadCore` 算法）和 Plan B（`BeadPersistence` 数据层）接起来，实现项目列表、新建流程（选图/裁剪/选格数/生成）、图纸编辑器（画笔/橡皮/吸色/撤销重做/颜色统计）、导出分享四大功能模块。

**Architecture:** SwiftUI + XcodeGen（`project.yml` 声明式生成 `.xcodeproj`，避免手工维护工程文件的合并冲突），本地 Swift Package 依赖 `BeadCore`/`BeadPersistence`。App 层只做 UI 编排和交互状态管理，所有算法/持久化逻辑复用已验证的 Package 代码。用 XCUITest 驱动真实模拟器交互作为主要验证手段——SwiftUI 视图的实际渲染效果和手势行为无法靠单元测试覆盖。

**Tech Stack:** SwiftUI, SwiftData（`@Query`/`@Environment(\.modelContext)`）, PhotosUI（`PhotosPicker`）, Vision（通过 BeadCore）, XCTest/XCUITest, XcodeGen。

## Global Constraints

- 依赖 Plan A（`BeadCore`）和 Plan B（`BeadPersistence`），本地路径依赖，二者必须先完成并通过各自的 `swift test`。
- 最低部署目标 iOS 17.0（与 Plan A/B 一致）。
- **UIImage/CGImage 像素-点坐标转换陷阱**：`UIImage.size` 返回的是点（point）坐标，不含 Retina 缩放系数；但 `CGImage.cropping(to:)` 操作的是像素（pixel）坐标。任何跨越这两个坐标系的计算（尤其是裁剪、坐标映射）必须显式乘以 `UIImage.scale` 做转换，否则在 2x/3x 设备上会裁剪到完全错误的区域——这不是边缘情况，是所有真实 iPhone（scale ≥ 2）都会触发的问题，必须用真机分辨率或非 1x 模拟器验证过才能算完成。
- SwiftUI 视图不能仅凭"编译通过"判断完成——每个交互相关任务必须有对应的 XCUITest 驱动真实模拟器验证，或至少截图检查渲染结果。系统级 UI（如 `PHPickerViewController` 相册选择器）无法被 XCUITest 稳定驱动，此类交互点需要提供一个仅在测试启动参数下生效的替代路径（本计划中是 `-UITestUseSampleImage`），不能因为"系统 UI 测不了"就跳过整条流程的端到端验证。
- 大网格（100×100 及以上）画布渲染必须使用 `Canvas`（immediate-mode 绘制）而不是每格一个 SwiftUI 视图，避免 40,000+ 视图导致的性能问题。
- 编辑器的持久化写入必须 debounce（拖拽涂色时每移动一格都触发一次 SwiftData `save()` 是不可接受的性能问题），且视图消失时要立即补一次同步保存，防止防抖窗口内的编辑丢失。
- 每个任务完成后必须跑 `xcodebuild ... test`（针对已配置好的 XCUITest target）或至少 `xcodebuild ... build` 确认可编译，禁止把编译失败的代码留给下一个任务。

---

## File Structure

```
pd/
  project.yml                                # XcodeGen 项目声明（App target + UI 测试 target + package 依赖）
  PerlerBeadApp/
    PerlerBeadApp.swift                       # @main App 入口，创建全局 ModelContainer
    AppTheme.swift                            # 珊瑚粉视觉主题 + RoundedCardButtonStyle
    ProjectListView.swift                     # 项目列表页 + 卡片
    GridSizePickerView.swift                  # 画布格数选择（预设 16~200 + 自定义）
    ImageCropView.swift                       # 方形裁剪交互
    NewProjectFlowView.swift                  # 新建项目流程状态机（选图→裁剪→选格数→生成）
    GridEditHistory.swift                     # 撤销/重做历史栈
    ColorUsageCalculator.swift                # 颜色用量统计（编辑器色板 + 导出图例共用）
    BeadGridCanvas.swift                      # Canvas 渲染的网格画布（画笔/橡皮/缩放手势）
    DebouncedGridSaver.swift                  # 防抖持久化封装
    PatternEditorView.swift                   # 图纸编辑器主页面
    ExportView.swift                          # 导出渲染 + 分享
  PerlerBeadAppUITests/
    PerlerBeadAppUITests.swift                # 端到端正确性测试（生成流程、跨重启持久化）
    PerlerBeadAppScreenshotWalkthrough.swift  # 全流程截图走查（视觉验证辅助）
```

每个文件职责单一：视觉主题、列表、新建流程、编辑器画布、编辑器容器、导出各自独立，编辑器容器（`PatternEditorView`）通过组合而非继承使用画布/防抖保存/撤销历史这几个更小的单元。

---

### Task 1: XcodeGen 项目脚手架 + App 入口

**Files:**
- Create: `project.yml`
- Create: `PerlerBeadApp/PerlerBeadApp.swift`

**Interfaces:**
- Consumes: `BeadProject`（`BeadPersistence`，Plan B）
- Produces: `@main struct PerlerBeadApp: App`，持有全局 `ModelContainer`

前提：Plan A 的 `BeadCore/` 和 Plan B 的 `BeadPersistence/` 已存在于仓库根目录且各自 `swift test` 通过。

- [ ] **Step 1: 安装 XcodeGen（如果尚未安装）**

```bash
brew install xcodegen
```

- [ ] **Step 2: 写 project.yml**

在仓库根目录创建 `project.yml`：

```yaml
name: PerlerBeadApp
options:
  bundleIdPrefix: com.liuyu.perlerbead
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
packages:
  BeadCore:
    path: BeadCore
  BeadPersistence:
    path: BeadPersistence
targets:
  PerlerBeadApp:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: PerlerBeadApp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.liuyu.perlerbead.PerlerBeadApp
        INFOPLIST_KEY_UILaunchScreen_Generation: "YES"
        INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "用于导入照片生成拼豆图纸"
        INFOPLIST_KEY_NSCameraUsageDescription: "用于拍照生成拼豆图纸"
        GENERATE_INFOPLIST_FILE: "YES"
        TARGETED_DEVICE_FAMILY: "1"
    dependencies:
      - package: BeadCore
        product: BeadCore
      - package: BeadPersistence
        product: BeadPersistence
  PerlerBeadAppUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: PerlerBeadAppUITests
    dependencies:
      - target: PerlerBeadApp
    settings:
      base:
        GENERATE_INFOPLIST_FILE: "YES"
schemes:
  PerlerBeadApp:
    build:
      targets:
        PerlerBeadApp: all
        PerlerBeadAppUITests: [test]
    test:
      targets:
        - PerlerBeadAppUITests
    run:
      config: Debug
```

- [ ] **Step 3: 创建 App 入口**

```bash
mkdir -p PerlerBeadApp PerlerBeadAppUITests
```

创建 `PerlerBeadApp/PerlerBeadApp.swift`：

```swift
import BeadPersistence
import SwiftData
import SwiftUI

@main
struct PerlerBeadApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: BeadProject.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
        }
        .modelContainer(modelContainer)
    }
}
```

- [ ] **Step 4: 生成 Xcode 项目并确认能找到可用模拟器**

```bash
xcodegen generate
xcrun simctl list devices available | grep "iPhone 17 Pro "
```
Expected: 输出一个可用的 iPhone 17 Pro 模拟器 UDID（后续任务用它跑测试；若设备名不同，替换为本机可用的 iPhone 模拟器）。

- [ ] **Step 5: Commit**

（此时 `ProjectListView` 尚不存在，编译会失败——先完成 Task 2 再一起提交，或者提交 project.yml 和 App 入口占位后继续。推荐先完成 Task 2 再一起 commit，见 Task 2 末尾。）

---

### Task 2: 视觉主题 + 项目列表页

**Files:**
- Create: `PerlerBeadApp/AppTheme.swift`
- Create: `PerlerBeadApp/ProjectListView.swift`

**Interfaces:**
- Consumes: `BeadProject`、`BeadProjectRepository`（`BeadPersistence`）
- Produces: `enum AppTheme`（颜色常量）、`struct RoundedCardButtonStyle: ButtonStyle`、`struct ProjectListView: View`、`struct ProjectCardView: View`

- [ ] **Step 1: 写视觉主题**

创建 `PerlerBeadApp/AppTheme.swift`：

```swift
import SwiftUI

enum AppTheme {
    static let coral = Color(red: 0.98, green: 0.55, blue: 0.60)
    static let coralLight = Color(red: 0.99, green: 0.93, blue: 0.94)
    static let cardBackground = Color(red: 0.99, green: 0.95, blue: 0.96)
    static let textPrimary = Color(red: 0.25, green: 0.18, blue: 0.20)

    static let cardCornerRadius: CGFloat = 16
}

struct RoundedCardButtonStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? AppTheme.coral.opacity(0.35) : AppTheme.coralLight)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
```

- [ ] **Step 2: 写项目列表页**

创建 `PerlerBeadApp/ProjectListView.swift`：

```swift
import BeadPersistence
import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BeadProject.modifiedAt, order: .reverse) private var projects: [BeadProject]
    @State private var showingNewProjectFlow = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(projects) { project in
                        NavigationLink(value: project) {
                            ProjectCardView(project: project)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("projectCard_\(project.id.uuidString)")
                    }
                }
                .padding()
            }
            .background(AppTheme.coralLight.ignoresSafeArea())
            .navigationTitle("我的拼豆图纸")
            .navigationDestination(for: BeadProject.self) { project in
                PatternEditorView(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProjectFlow = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.coral)
                    }
                    .accessibilityIdentifier("newProjectButton")
                }
            }
            .sheet(isPresented: $showingNewProjectFlow) {
                NewProjectFlowView(onProjectCreated: { project in
                    showingNewProjectFlow = false
                    navigationPath.append(project)
                })
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "还没有拼豆图纸",
                        systemImage: "square.grid.3x3",
                        description: Text("点击右上角 + 开始新建")
                    )
                }
            }
        }
    }

    private func deleteProject(_ project: BeadProject) {
        let repository = BeadProjectRepository(context: modelContext)
        try? repository.delete(project)
    }
}

struct ProjectCardView: View {
    let project: BeadProject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnailData = project.thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))

            Text(project.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Text(project.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
    }
}
```

**为什么导航用 `NavigationPath` 而不是让新建流程自己 `dismiss()`**：`NewProjectFlowView` 是以 `.sheet` 弹出的，生成成功后既要关闭这个 sheet，又要在**列表页自己的 `NavigationStack`** 里推入新项目的编辑器——这两件事必须由持有 `navigationPath` 的父视图（`ProjectListView`）来做，`NewProjectFlowView` 自己的 `dismiss()` 只能关闭 sheet，管不到父视图的导航栈。因此 `NewProjectFlowView` 通过 `onProjectCreated` 回调把创建好的 `BeadProject` 交还给父视图。

- [ ] **Step 3: 编译确认（预期仍会因缺少 NewProjectFlowView/PatternEditorView 而失败，属于正常中间状态）**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```
Expected: 报错缺少 `NewProjectFlowView`、`PatternEditorView` 类型——这是预期的中间状态，继续 Task 3~6 补齐后再验证。

---

### Task 3: 画布格数选择器

**Files:**
- Create: `PerlerBeadApp/GridSizePickerView.swift`

**Interfaces:**
- Produces: `enum GridSizeOption: Int, CaseIterable, Identifiable`（16/24/36/48/52/68/72/78/96/104/108/128/156/200）、`struct GridSizePickerContent: View`（`@Binding var selectedSize: Int`, `var onSelect: (() -> Void)?`）、`struct GridSizePickerSheet: View`

- [ ] **Step 1: 写选择器**

创建 `PerlerBeadApp/GridSizePickerView.swift`：

```swift
import PhotosUI
import SwiftUI

enum GridSizeOption: Int, CaseIterable, Identifiable {
    case s16 = 16, s24 = 24, s36 = 36, s48 = 48, s52 = 52, s68 = 68
    case s72 = 72, s78 = 78, s96 = 96, s104 = 104, s108 = 108, s128 = 128
    case s156 = 156, s200 = 200

    var id: Int { rawValue }
    var label: String { "\(rawValue)×\(rawValue)" }
}

/// Pure grid-size selection content: no navigation chrome, so it can be embedded directly in a
/// flow step (NewProjectFlowView) or wrapped in a standalone sheet (GridSizePickerSheet).
struct GridSizePickerContent: View {
    @Binding var selectedSize: Int
    var onSelect: (() -> Void)?

    @State private var customSizeText: String = ""
    @State private var showingCustomField = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(GridSizeOption.allCases) { option in
                    Button {
                        selectedSize = option.rawValue
                        onSelect?()
                    } label: {
                        Text(option.label)
                    }
                    .buttonStyle(RoundedCardButtonStyle(isSelected: selectedSize == option.rawValue))
                    .accessibilityIdentifier("gridSizeOption_\(option.rawValue)")
                }

                Button {
                    showingCustomField = true
                } label: {
                    Text("自定义")
                }
                .buttonStyle(RoundedCardButtonStyle(isSelected: showingCustomField))
            }
            .padding()

            if showingCustomField {
                HStack {
                    TextField("输入格数，如 60", text: $customSizeText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("确定") {
                        if let value = Int(customSizeText), value > 0 {
                            selectedSize = value
                            onSelect?()
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Standalone sheet wrapper for contexts where the grid size picker needs its own dismiss
/// affordance (e.g. re-opened from within the pattern editor to change an existing project's
/// grid size), as opposed to being one step inside NewProjectFlowView's own navigation flow.
struct GridSizePickerSheet: View {
    @Binding var selectedSize: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GridSizePickerContent(selectedSize: $selectedSize, onSelect: { dismiss() })
                .background(Color.white.ignoresSafeArea())
                .navigationTitle("板子格数")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.coral)
                        }
                    }
                }
        }
    }
}
```

**为什么拆成 `GridSizePickerContent`（无导航栏）+ `GridSizePickerSheet`（带导航栏和关闭按钮）两层**：新建流程（`NewProjectFlowView`）需要把格数选择嵌入自己的导航栏之下、作为其中一步，此时选中一个格子不应该关闭整个新建流程的 sheet；而"重新调整已有项目的格数"这种独立场景需要自己的关闭按钮。把无 chrome 的选择逻辑单独抽出为 `GridSizePickerContent`，两种场景各自决定 `onSelect` 要不要触发 dismiss，避免了"选个格数就把整个新建流程弹层关掉"这类误绑定。

- [ ] **Step 2: 编译确认无新增错误**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```
Expected: 仍然报缺少 `NewProjectFlowView`/`PatternEditorView`，但不应再报 `GridSizePickerContent`/`GridSizePickerSheet` 相关错误。

---

### Task 4: 图片裁剪交互

**Files:**
- Create: `PerlerBeadApp/ImageCropView.swift`

**Interfaces:**
- Produces: `struct ImageCropView: View`（`let sourceImage: UIImage`, `let onConfirm: (UIImage) -> Void`, `let onCancel: () -> Void`）

⚠️ **关键陷阱**：`UIImage.size` 是点坐标，`CGImage.cropping(to:)` 是像素坐标。裁剪计算必须显式乘以 `sourceImage.scale` 做转换，否则在 Retina 设备（scale 2x/3x，即几乎所有真实 iPhone）上会裁到错误区域。本任务的实现已经包含这个修正；如果后续修改这个文件，务必保留 `pixelScale` 相关的乘法运算，不要"简化"掉。

- [ ] **Step 1: 写裁剪视图**

创建 `PerlerBeadApp/ImageCropView.swift`：

```swift
import SwiftUI

/// A square crop view: the source image fills the crop frame (aspect-fill) and the user can
/// drag to reposition which part of the image is visible inside the fixed square frame.
/// Produces a cropped UIImage clipped to that square when `onConfirm` is invoked.
struct ImageCropView: View {
    let sourceImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    private let cropSize: CGFloat = 320

    var body: some View {
        VStack(spacing: 24) {
            Text("拖动调整取景范围")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let fillSize = aspectFillSize(imageSize: sourceImage.size, boundingSize: CGSize(width: cropSize, height: cropSize))
                ZStack {
                    Color.black
                    Image(uiImage: sourceImage)
                        .resizable()
                        .frame(width: fillSize.width, height: fillSize.height)
                        .offset(offset)
                }
                .frame(width: cropSize, height: cropSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.coral, lineWidth: 3)
                )
                .position(x: geometry.size.width / 2, y: cropSize / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStart = offset
                        }
                )
            }
            .frame(height: cropSize)

            HStack(spacing: 16) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("确定") {
                    let cropped = renderCroppedImage()
                    onConfirm(cropped)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coral)
                .accessibilityIdentifier("confirmCropButton")
            }
        }
        .padding()
    }

    private func aspectFillSize(imageSize: CGSize, boundingSize: CGSize) -> CGSize {
        let scale = max(boundingSize.width / imageSize.width, boundingSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Renders the currently visible square crop region to a new UIImage at the source image's
    /// native resolution (scaled proportionally), so downstream processing works from full detail
    /// rather than the small on-screen preview size.
    private func renderCroppedImage() -> UIImage {
        let fillSize = aspectFillSize(imageSize: sourceImage.size, boundingSize: CGSize(width: cropSize, height: cropSize))
        let scaleToNative = sourceImage.size.width / fillSize.width

        // Everything up to here is in "points" (UIImage.size is points, not pixels), but
        // CGImage.cropping(to:) operates on the backing CGImage's pixel buffer. On any Retina
        // device (scale 2x/3x, i.e. virtually every real iPhone) skipping this conversion crops
        // the wrong region entirely — e.g. on a 3x image it only ever sees the top-left third.
        let cropOriginInNativePoints = CGPoint(
            x: (fillSize.width - cropSize) / 2 - offset.width,
            y: (fillSize.height - cropSize) / 2 - offset.height
        )
        let pixelScale = sourceImage.scale
        let cropRectInPixelSpace = CGRect(
            x: cropOriginInNativePoints.x * scaleToNative * pixelScale,
            y: cropOriginInNativePoints.y * scaleToNative * pixelScale,
            width: cropSize * scaleToNative * pixelScale,
            height: cropSize * scaleToNative * pixelScale
        ).intersection(CGRect(
            x: 0, y: 0,
            width: sourceImage.size.width * pixelScale,
            height: sourceImage.size.height * pixelScale
        ))

        guard let cgImage = sourceImage.cgImage?.cropping(to: cropRectInPixelSpace) else {
            return sourceImage
        }
        return UIImage(cgImage: cgImage, scale: pixelScale, orientation: sourceImage.imageOrientation)
    }
}
```

- [ ] **Step 2: 编译确认无新增错误**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```

---

### Task 5: 新建项目流程状态机

**Files:**
- Create: `PerlerBeadApp/NewProjectFlowView.swift`

**Interfaces:**
- Consumes: `PatternGenerationOptions`、`PatternGenerator`、`VisionSaliencyImportanceMapProvider`（`BeadCore`）、`BeadProjectRepository`（`BeadPersistence`）、`GridSizePickerContent`（Task 3）、`ImageCropView`（Task 4）、`RoundedCardButtonStyle`/`AppTheme`（Task 2）
- Produces: `struct NewProjectFlowView: View`（`init(onProjectCreated: @escaping (BeadProject) -> Void)`）

**关键设计点——测试替代路径**：系统的 `PhotosPicker`/`PHPickerViewController` 运行在独立进程，XCUITest 无法可靠驱动它完成"选择一张照片"这个操作。因此当 App 以 `-UITestUseSampleImage` 启动参数启动时，界面上会多出一个"使用测试图片"按钮，用程序生成的合成图片（不依赖任何外部图片资源）替代真实相册选择，从而让 UI 测试能够走通"新建→裁剪→选格数→生成→进入编辑器"的完整链路。这不是为了应付测试而添加的花招，而是保证核心业务流程能被自动化验证的必要设计。

- [ ] **Step 1: 写新建流程**

创建 `PerlerBeadApp/NewProjectFlowView.swift`：

```swift
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
```

- [ ] **Step 2: 编译确认（预期仍缺 PatternEditorView）**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```
Expected: 只报缺少 `PatternEditorView`。

---

### Task 6: 编辑器支持类型（撤销历史 + 颜色统计 + Canvas 画布 + 防抖保存）

**Files:**
- Create: `PerlerBeadApp/GridEditHistory.swift`
- Create: `PerlerBeadApp/ColorUsageCalculator.swift`
- Create: `PerlerBeadApp/BeadGridCanvas.swift`
- Create: `PerlerBeadApp/DebouncedGridSaver.swift`

**Interfaces:**
- Consumes: `BeadGrid`、`MardColor`（`BeadCore`）、`BeadProject`、`BeadProjectRepository`（`BeadPersistence`）
- Produces:
  - `final class GridEditHistory { func recordBeforeEdit(_:); var canUndo/canRedo: Bool; func undo(current:) -> BeadGrid?; func redo(current:) -> BeadGrid? }`
  - `struct ColorUsage: Identifiable { let color: MardColor; let count: Int }`、`enum ColorUsageCalculator { static func usages(for: BeadGrid) -> [ColorUsage] }`
  - `struct BeadGridCanvas: View`（`onCellTouched: ((Int, Int, Bool) -> Void)?`，第三个参数标记是否为本次连续触摸的第一格）
  - `final class DebouncedGridSaver { func scheduleSave(_:); func saveImmediately(_:) }`

**关键设计点——一笔画只记录一次撤销历史**：`BeadGridCanvas` 的手势是 `DragGesture(minimumDistance: 0)`，单击也会先触发一次 `onChanged` 再触发一次 `onEnded`。如果用"`onChanged` 时不记录、`onEnded` 时才记录"的方式区分"拖动中"和"松手"，会导致即使是最简单的单击，`onChanged` 已经先把颜色画上去了，`onEnded` 记录的"撤销前状态"其实是画完之后的状态——undo 完全失效。正确做法是用 `isStrokeInProgress` 标记"当前是否处于一次连续触摸中"，只在每次触摸的**第一个**格子（`isStrokeStart == true`）时记录撤销历史，同一笔画后续所有格子都不再重复记录。

- [ ] **Step 1: 写撤销/重做历史**

创建 `PerlerBeadApp/GridEditHistory.swift`：

```swift
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
```

- [ ] **Step 2: 写颜色用量统计**

创建 `PerlerBeadApp/ColorUsageCalculator.swift`：

```swift
import BeadCore
import Foundation

struct ColorUsage: Identifiable {
    let color: MardColor
    let count: Int
    var id: String { color.code }
}

enum ColorUsageCalculator {
    static func usages(for grid: BeadGrid) -> [ColorUsage] {
        var counts: [String: Int] = [:]
        var colorByCode: [String: MardColor] = [:]
        for color in grid.colors {
            counts[color.code, default: 0] += 1
            colorByCode[color.code] = color
        }
        return counts
            .compactMap { code, count in colorByCode[code].map { ColorUsage(color: $0, count: count) } }
            .sorted { $0.count > $1.count }
    }
}
```

- [ ] **Step 3: 写 Canvas 网格画布**

创建 `PerlerBeadApp/BeadGridCanvas.swift`：

```swift
import BeadCore
import SwiftUI

/// Renders a BeadGrid with SwiftUI's Canvas (immediate-mode drawing) rather than one view per
/// cell — a 200x200 grid is 40,000 cells, and 40,000 SwiftUI views would be prohibitively slow
/// to lay out and update on every edit.
struct BeadGridCanvas: View {
    let grid: BeadGrid
    let highlightedColorCode: String?
    /// Called for every cell touched during a stroke. `isStrokeStart` is true only for the very
    /// first cell of a given continuous touch — callers use this to record undo history exactly
    /// once per stroke rather than once per cell (which would make undo a no-op on drags) or
    /// once per gesture-end (which would record history *after* the edit already happened).
    var onCellTouched: ((Int, Int, _ isStrokeStart: Bool) -> Void)?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isStrokeInProgress = false

    private var cellSize: CGFloat { 10 * scale }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Canvas { context, _ in
                for row in 0..<grid.rows {
                    for col in 0..<grid.columns {
                        let color = grid.color(col: col, row: row)
                        let rect = CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                        let isDimmed = highlightedColorCode != nil && highlightedColorCode != color.code
                        let uiColor = Color(red: color.red, green: color.green, blue: color.blue)
                        context.fill(Path(rect), with: .color(isDimmed ? uiColor.opacity(0.15) : uiColor))
                        context.stroke(Path(rect), with: .color(.black.opacity(0.08)), lineWidth: 0.5)
                    }
                }
            }
            .frame(width: CGFloat(grid.columns) * cellSize, height: CGFloat(grid.rows) * cellSize)
            .gesture(strokeGesture)
        }
        .gesture(magnificationGesture)
    }

    private var strokeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let col = Int(value.location.x / cellSize)
                let row = Int(value.location.y / cellSize)
                guard col >= 0, col < grid.columns, row >= 0, row < grid.rows else { return }
                onCellTouched?(col, row, !isStrokeInProgress)
                isStrokeInProgress = true
            }
            .onEnded { _ in
                isStrokeInProgress = false
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.3, min(4.0, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}
```

- [ ] **Step 4: 写防抖保存**

创建 `PerlerBeadApp/DebouncedGridSaver.swift`：

```swift
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
```

- [ ] **Step 5: 编译确认（预期仍缺 PatternEditorView/ExportView）**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```

---

### Task 7: 图纸编辑器主页面

**Files:**
- Create: `PerlerBeadApp/PatternEditorView.swift`

**Interfaces:**
- Consumes: 全部前置任务类型
- Produces: `struct PatternEditorView: View`（`let project: BeadProject`）

- [ ] **Step 1: 写编辑器**

创建 `PerlerBeadApp/PatternEditorView.swift`：

```swift
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

    var body: some View {
        VStack(spacing: 0) {
            if let grid {
                BeadGridCanvas(
                    grid: grid,
                    highlightedColorCode: highlightedColorCode,
                    onCellTouched: { col, row, isStrokeStart in
                        handleCellInteraction(col: col, row: row, isStrokeStart: isStrokeStart)
                    }
                )
                .background(Color.white)

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
                    .disabled(grid == nil)
                    .accessibilityIdentifier("exportButton")
            }
        }
        .sheet(isPresented: $showingExport) {
            if let grid {
                ExportView(grid: grid, projectName: project.name)
            }
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
        do {
            grid = try repository.decodeGrid(for: project, palette: MardPalette.standard221)
        } catch {
            loadError = "图纸数据读取失败：\(error.localizedDescription)"
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
```

- [ ] **Step 2: 编译确认（预期仍缺 ExportView）**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```

---

### Task 8: 导出渲染 + 分享

**Files:**
- Create: `PerlerBeadApp/ExportView.swift`

**Interfaces:**
- Consumes: `BeadGrid`（`BeadCore`）、`ColorUsageCalculator`（Task 6）
- Produces: `enum PatternExportRenderer { static func render(_: BeadGrid, cellSize: CGFloat) -> UIImage }`、`struct ExportView: View`、`struct ShareSheet: UIViewControllerRepresentable`

这与 `BeadPersistence.ThumbnailRenderer`（Plan B）是两个不同的渲染器：`ThumbnailRenderer` 产出无标签的小缩略图用于项目列表卡片；这里的 `PatternExportRenderer` 产出带网格线、行列坐标、颜色图例的完整可打印图纸，服务于"用户要照着这张图实际去拼豆子"的场景，两者渲染目标不同，不应合并成一个函数。

- [ ] **Step 1: 写导出渲染器和视图**

创建 `PerlerBeadApp/ExportView.swift`：

```swift
import BeadCore
import SwiftUI

/// Renders a full export image: one cell per bead color, with grid lines and row/column index
/// labels along the top and left edges, plus a legend of color codes and usage counts below.
/// This is intentionally separate from BeadPersistence's ThumbnailRenderer (which produces a
/// small, label-free preview for the project list) — the export needs to be legible enough to
/// actually bead from.
enum PatternExportRenderer {
    static func render(_ grid: BeadGrid, cellSize: CGFloat = 24) -> UIImage {
        let labelMargin: CGFloat = 28
        let legendRowHeight: CGFloat = 28
        let usages = ColorUsageCalculator.usages(for: grid)
        let legendHeight = CGFloat(usages.count) * legendRowHeight + 16

        let gridWidth = CGFloat(grid.columns) * cellSize
        let gridHeight = CGFloat(grid.rows) * cellSize
        let canvasSize = CGSize(width: labelMargin + gridWidth, height: labelMargin + gridHeight + legendHeight)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            drawGrid(grid, cellSize: cellSize, origin: CGPoint(x: labelMargin, y: labelMargin), context: context.cgContext)
            drawLabels(grid, cellSize: cellSize, origin: CGPoint(x: labelMargin, y: labelMargin))
            drawLegend(usages, origin: CGPoint(x: 8, y: labelMargin + gridHeight + 8), rowHeight: legendRowHeight)
        }
    }

    private static func drawGrid(_ grid: BeadGrid, cellSize: CGFloat, origin: CGPoint, context: CGContext) {
        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                let rect = CGRect(x: origin.x + CGFloat(col) * cellSize, y: origin.y + CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
                context.fill(rect)
                UIColor.black.withAlphaComponent(0.15).setStroke()
                context.stroke(rect, width: 0.5)
            }
        }
    }

    private static func drawLabels(_ grid: BeadGrid, cellSize: CGFloat, origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
        ]
        let labelInterval = max(1, grid.columns / 20)
        for col in stride(from: 0, to: grid.columns, by: labelInterval) {
            let text = "\(col + 1)"
            text.draw(at: CGPoint(x: origin.x + CGFloat(col) * cellSize + 2, y: origin.y - 16), withAttributes: attributes)
        }
        let rowLabelInterval = max(1, grid.rows / 20)
        for row in stride(from: 0, to: grid.rows, by: rowLabelInterval) {
            let text = "\(row + 1)"
            text.draw(at: CGPoint(x: 4, y: origin.y + CGFloat(row) * cellSize + 2), withAttributes: attributes)
        }
    }

    private static func drawLegend(_ usages: [ColorUsage], origin: CGPoint, rowHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.black,
        ]
        for (index, usage) in usages.enumerated() {
            let y = origin.y + CGFloat(index) * rowHeight
            let swatchRect = CGRect(x: origin.x, y: y, width: 20, height: 20)
            UIColor(red: usage.color.red, green: usage.color.green, blue: usage.color.blue, alpha: 1).setFill()
            UIBezierPath(rect: swatchRect).fill()
            let text = "\(usage.color.code)  ×\(usage.count)"
            text.draw(at: CGPoint(x: origin.x + 28, y: y + 2), withAttributes: attributes)
        }
    }
}

struct ExportView: View {
    let grid: BeadGrid
    let projectName: String
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let renderedImage {
                    Image(uiImage: renderedImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: renderedImage.size.width, height: renderedImage.size.height)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("导出图纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("分享") { showingShareSheet = true }
                        .disabled(renderedImage == nil)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let renderedImage {
                    ShareSheet(items: [renderedImage])
                }
            }
            .task {
                renderedImage = PatternExportRenderer.render(grid)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 2: 编译确认全部通过**

```bash
xcodegen generate
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit（App 主体代码首次完整可编译）**

```bash
cd /Users/liuyu22/Desktop/pd
git add project.yml PerlerBeadApp/
git commit -m "feat: add PerlerBeadApp SwiftUI layer wiring BeadCore + BeadPersistence"
```

---

### Task 9: 端到端 UI 测试 + 视觉验证

**Files:**
- Create: `PerlerBeadAppUITests/PerlerBeadAppUITests.swift`
- Create: `PerlerBeadAppUITests/PerlerBeadAppScreenshotWalkthrough.swift`

**Interfaces:**
- 无新公开接口；本任务通过 XCUITest 驱动真实模拟器验证 Task 1~8 组装出的完整交互链路。

**为什么两个测试文件而不是一个**：`PerlerBeadAppUITests` 是正确性断言（流程能走通、数据能持久化），`PerlerBeadAppScreenshotWalkthrough` 是纯视觉走查（附加每一步的截图供人工检视设计还原度），后者不应该因为断言变严格而失败，混在一起会让"新增一个断言"和"新增一张截图"这两种不同性质的改动互相干扰。

- [ ] **Step 1: 写正确性测试**

创建 `PerlerBeadAppUITests/PerlerBeadAppUITests.swift`：

```swift
import XCTest

final class PerlerBeadAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Drives the full happy path end to end: new project -> sample image (substituting for the
    /// system photo picker, which can't be reliably automated) -> crop confirm -> grid size pick
    /// -> generate -> lands in the pattern editor -> export sheet opens with a rendered image.
    /// This is the primary evidence that BeadCore + BeadPersistence + the SwiftUI layer are wired
    /// together correctly, not just that each compiles in isolation.
    func testFullProjectCreationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()

        let newProjectButton = app.buttons["newProjectButton"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 5))
        newProjectButton.tap()

        let useSampleImageButton = app.buttons["useSampleImageButton"]
        XCTAssertTrue(useSampleImageButton.waitForExistence(timeout: 5))
        useSampleImageButton.tap()

        let confirmCropButton = app.buttons["confirmCropButton"]
        XCTAssertTrue(confirmCropButton.waitForExistence(timeout: 5))
        confirmCropButton.tap()

        let gridSizeOption16 = app.buttons["gridSizeOption_16"]
        XCTAssertTrue(gridSizeOption16.waitForExistence(timeout: 5))
        gridSizeOption16.tap()

        let generateButton = app.buttons["generatePatternButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        // Generation runs the full BeadCore pipeline (Vision saliency + SLIC + palette
        // optimization + noise cleanup) on a background thread; on a 16x16 grid this should
        // complete well within 30s even on a slow CI simulator.
        let exportButton = app.buttons["exportButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 30))

        exportButton.tap()
        let closeButton = app.buttons["关闭"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
    }

    /// Verifies the project list persists and re-displays a project after the app "restarts"
    /// (a fresh XCUIApplication launch reconnects to the same on-disk SwiftData store), proving
    /// BeadProjectRepository's persistence is real and not just in-memory for the session.
    func testCreatedProjectPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()

        app.buttons["newProjectButton"].tap()
        app.buttons["useSampleImageButton"].tap()
        app.buttons["confirmCropButton"].tap()
        app.buttons["gridSizeOption_16"].tap()
        app.buttons["generatePatternButton"].tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launch()

        let projectCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'projectCard_'")
        let anyProjectCard = relaunched.buttons.matching(projectCardPredicate).firstMatch
        XCTAssertTrue(anyProjectCard.waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 2: 写截图走查测试**

创建 `PerlerBeadAppUITests/PerlerBeadAppScreenshotWalkthrough.swift`：

```swift
import XCTest

/// Not a correctness test — walks the flow and attaches a screenshot at each step so the
/// visual design (coral theme, grid canvas, palette, export layout) can be reviewed without
/// relying on unreliable host-level mouse-click simulation in this environment.
final class PerlerBeadAppScreenshotWalkthrough: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureScreenshotsAlongFullFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()
        attachScreenshot(app, name: "01-project-list-empty")

        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.buttons["useSampleImageButton"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "02-pick-image-step")

        app.buttons["useSampleImageButton"].tap()
        XCTAssertTrue(app.buttons["confirmCropButton"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "03-crop-step")

        app.buttons["confirmCropButton"].tap()
        XCTAssertTrue(app.buttons["gridSizeOption_16"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "04-grid-size-step")

        app.buttons["gridSizeOption_48"].tap()
        app.buttons["generatePatternButton"].tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))
        // Give the editor a beat to finish laying out the canvas + palette after the nav push.
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app, name: "05-pattern-editor")

        app.buttons["exportButton"].tap()
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app, name: "06-export-view")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

- [ ] **Step 3: 运行完整 UI 测试套件**

```bash
xcodegen generate
xcrun simctl list devices available | grep "iPhone 17 Pro "
```

记下输出的 UDID（下方命令中替换 `<UDID>`），然后：

```bash
xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp \
  -destination 'platform=iOS Simulator,id=<UDID>' test 2>&1 | tail -40
```
Expected: `Test Suite 'All tests' passed`，共 3 个测试（`testFullProjectCreationFlow`、`testCreatedProjectPersistsAcrossRelaunch`、`testCaptureScreenshotsAlongFullFlow`）全部通过。

- [ ] **Step 4: 提取并检视截图，确认视觉还原度**

```bash
LATEST_RESULT=$(ls -td /Users/liuyu22/Library/Developer/Xcode/DerivedData/PerlerBeadApp-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool export attachments --path "$LATEST_RESULT" --output-path /tmp/screenshots_review
```

用 Read 工具逐张查看 `/tmp/screenshots_review/` 里的 6 张截图，确认：
1. 项目列表空状态显示珊瑚粉主题和引导文案
2. 新建流程的选图步骤显示"从相册选择照片"按钮
3. 裁剪步骤图片正确显示在裁剪框内（**特别检查**：如果测试图片的居中方块在截图里显示为边角的细长条而不是居中的方块，说明 Task 4 的像素/点坐标转换出现了回归，需要重新检查 `ImageCropView.renderCroppedImage()` 里的 `pixelScale` 计算）
4. 格数选择步骤布局和你的参考截图风格一致
5. 编辑器页面网格、色板、工具栏均正确渲染，颜色比例与原图裁剪区域吻合
6. 导出页面网格线、坐标标签清晰可读

- [ ] **Step 5: Commit**

```bash
git add PerlerBeadAppUITests/
git commit -m "test: add end-to-end UI tests and screenshot walkthrough for PerlerBeadApp"
```

---

## Plan Self-Review Notes

- **Spec 覆盖检查**：主设计文档"功能模块与交互流程"章节的四个页面（项目列表、新建流程、图纸编辑器、导出/分享）分别对应 Task 2、Task 3~5、Task 6~7、Task 8。"自动保存（debounce 落盘）"由 Task 6 的 `DebouncedGridSaver` 实现。"重新生成前二次确认覆盖手动修改"这一交互细节本计划未实现（当前重新调整格数只在新建流程内出现，尚未提供"编辑器内重新生成"入口）——这是一个已知缺口，留待后续迭代补充，不影响当前四个核心页面的可用性。
- **占位符检查**：全部 9 个任务的代码块均为实际编译、真实模拟器运行验证过的代码，无 TBD。
- **类型一致性检查**：`BeadGrid`、`MardColor`、`BeadProject`、`BeadProjectRepository` 等跨 Package 类型在各任务中的方法签名一致（已通过 `xcodebuild build`/`xcodebuild test` 交叉验证）。
- **真实发现的 bug 记录**：Task 4 的像素/点坐标转换问题是在本计划实际执行过程中，通过截图走查发现的真实缺陷（测试图片的居中方块渲染成了边角细条），并非假设性风险——修复前的错误版本在任何 Retina 设备上都会裁剪到错误区域。这也是为什么 Task 9 的验证步骤专门强调要检视裁剪步骤的截图，而不是仅依赖"编译通过"或"断言通过"。
- **未覆盖范围**：项目卡片的删除交互（`ProjectListView.deleteProject` 已实现但未接入任何手势/按钮触发入口）、颜色卡自定义色卡切换、图纸尺寸的"锁定比例"选项等均超出本计划范围，属于后续迭代。
