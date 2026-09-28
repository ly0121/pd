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
