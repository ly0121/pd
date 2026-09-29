import BeadPersistence
import PhotosUI
import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BeadProject.modifiedAt, order: .reverse) private var projects: [BeadProject]
    @State private var showingNewProjectFlow = false
    @State private var showingPhotosPicker = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var navigationPath = NavigationPath()
    @State private var isSelecting = false
    @State private var selectedProjectIDs: Set<PersistentIdentifier> = []
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(projects) { project in
                        if isSelecting {
                            Button {
                                toggleSelection(project)
                            } label: {
                                ProjectCardView(
                                    project: project,
                                    isSelected: selectedProjectIDs.contains(project.persistentModelID),
                                    showsSelectionIndicator: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("projectCard_\(project.id.uuidString)")
                        } else {
                            NavigationLink(value: project) {
                                ProjectCardView(project: project)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("projectCard_\(project.id.uuidString)")
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.coralLight.ignoresSafeArea())
            .navigationDestination(for: BeadProject.self) { project in
                PatternEditorView(project: project)
            }
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            isSelecting = false
                            selectedProjectIDs.removeAll()
                        }
                        .accessibilityIdentifier("cancelSelectButton")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Text("删除(\(selectedProjectIDs.count))")
                        }
                        .disabled(selectedProjectIDs.isEmpty)
                        .accessibilityIdentifier("deleteSelectedButton")
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            // UI tests can't reliably drive the system PHPickerViewController (it
                            // runs out of process), so under -UITestUseSampleImage they skip the
                            // real picker entirely and open the flow directly at its own pickImage
                            // step, which offers a "使用测试图片" substitute.
                            if ProcessInfo.processInfo.arguments.contains("-UITestUseSampleImage") {
                                showingNewProjectFlow = true
                            } else {
                                showingPhotosPicker = true
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppTheme.coral)
                        }
                        .accessibilityIdentifier("newProjectButton")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("选择") { isSelecting = true }
                            .disabled(projects.isEmpty)
                            .accessibilityIdentifier("selectModeButton")
                    }
                }
            }
            // Attached at this level (not inside NewProjectFlowView) so tapping "+" presents the
            // system photo picker directly, with no intermediate screen — .photosPicker requires
            // its host view to already be on screen before it can animate in, so if this lived
            // inside the "新建图纸" sheet, that sheet's own first frame would flash before the
            // picker appeared on top of it.
            .photosPicker(isPresented: $showingPhotosPicker, selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    guard let data = try? await newValue.loadTransferable(type: Data.self),
                          let image = UIImage(data: data)
                    else { return }
                    pickedImage = image
                    showingNewProjectFlow = true
                }
            }
            .navigationDestination(isPresented: $showingNewProjectFlow) {
                NewProjectFlowView(initialImage: pickedImage, onProjectCreated: { project in
                    showingNewProjectFlow = false
                    pickedImage = nil
                    photosPickerItem = nil
                    navigationPath.append(project)
                })
            }
            .confirmationDialog(
                "删除 \(selectedProjectIDs.count) 张图纸？",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    deleteSelectedProjects()
                }
                .accessibilityIdentifier("confirmDeleteSelectedButton")
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复。")
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

    private func toggleSelection(_ project: BeadProject) {
        let id = project.persistentModelID
        if selectedProjectIDs.contains(id) {
            selectedProjectIDs.remove(id)
        } else {
            selectedProjectIDs.insert(id)
        }
    }

    private func deleteSelectedProjects() {
        let repository = BeadProjectRepository(context: modelContext)
        for project in projects where selectedProjectIDs.contains(project.persistentModelID) {
            try? repository.delete(project)
        }
        selectedProjectIDs.removeAll()
        isSelecting = false
    }
}

struct ProjectCardView: View {
    let project: BeadProject
    var isSelected: Bool = false
    var showsSelectionIndicator: Bool = false

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
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if showsSelectionIndicator {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? AppTheme.coral : .white)
                        .background(Circle().fill(isSelected ? .white : .black.opacity(0.3)).padding(2))
                        .padding(6)
                }
            }

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
