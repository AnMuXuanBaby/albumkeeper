import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore

    @State private var videosOnly = false
    @State private var viewerItem: PhotoItem?

    private var list: [PhotoItem] {
        let base = videosOnly ? library.items.filter { $0.isVideo } : library.items
        return base.sorted { (library.sizes[$0.id] ?? 0) > (library.sizes[$1.id] ?? 0) }
    }

    private var topItems: [PhotoItem] {
        Array(list.prefix(300))
    }

    private var videoBytes: Int64 {
        library.items.reduce(Int64(0)) { partial, item in
            guard item.isVideo else { return partial }
            return partial + (library.sizes[item.id] ?? 0)
        }
    }

    private var maxItemBytes: Int64 {
        library.sizes.values.max() ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                content
            }
            .navigationTitle("体积管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selection.isSelecting ? "取消" : "选择") {
                        selection.isSelecting.toggle()
                        if !selection.isSelecting {
                            selection.selected.removeAll()
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if selection.isSelecting {
                        BatchActionsBar(visibleIDs: topItems.map { $0.id })
                    }
                    MarkedBar()
                }
            }
            .fullScreenCover(item: $viewerItem) { item in
                AssetViewer(item: item)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !library.sizeIndexComplete {
            measureState
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    statsRow
                    Toggle("只看视频", isOn: $videosOnly)
                        .font(.system(size: 12))
                        .tint(Theme.accent)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 4)

                    LazyVStack(spacing: 6) {
                        ForEach(topItems) { item in
                            Button {
                                handleTap(item)
                            } label: {
                                StorageRow(item: item,
                                           selected: selection.selected.contains(item.id),
                                           showSelection: selection.isSelecting)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var measureState: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.85))
            Text("统计每个文件的实际体积")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("一次统计后即可按体积排序，找出最占空间的视频和大图。")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if library.isMeasuring {
                ProgressView(value: library.sizeProgress)
                    .tint(Theme.accent)
                    .padding(.horizontal, 30)
                Text("\(Int(library.sizeProgress * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.accent)
            } else {
                Button("开始统计") {
                    Task { await library.measureSizes() }
                }
                .buttonStyle(FillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            StatTile(title: "总体积", value: Fmt.bytes(library.totalBytes))
            StatTile(title: "视频", value: Fmt.bytes(videoBytes), tint: Theme.mint)
            StatTile(title: "最大单项", value: Fmt.bytes(maxItemBytes), tint: Theme.danger)
        }
    }

    private func handleTap(_ item: PhotoItem) {
        if selection.isSelecting {
            selection.toggle(item.id)
        } else {
            viewerItem = item
        }
    }
}

struct StorageRow: View {
    let item: PhotoItem
    let selected: Bool
    let showSelection: Bool
    @EnvironmentObject private var library: PhotoLibraryService

    init(item: PhotoItem, selected: Bool, showSelection: Bool) {
        self.item = item
        self.selected = selected
        self.showSelection = showSelection
    }

    var body: some View {
        HStack(spacing: 10) {
            AssetThumbnail(item: item)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.isVideo ? "视频 · \(Fmt.duration(item.duration))" : "照片")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text("\(Fmt.dateTime(item.creationDate)) · \(item.pixelWidth)×\(item.pixelHeight)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Fmt.sizeLabel(library.sizes[item.id]))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.accent)

            if showSelection {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(selected ? Theme.accent : Theme.textSecondary)
            }
        }
        .padding(8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1)
        )
    }
}
