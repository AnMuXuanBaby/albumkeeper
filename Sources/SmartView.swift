import SwiftUI

struct SmartView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @EnvironmentObject private var tags: TagStore
    @StateObject private var scanner = SmartScanner()

    @State private var scanTask: Task<Void, Never>?
    @State private var allowNetwork = false

    private var counts: [String: Int] {
        var result: [String: Int] = [:]
        for item in library.items where item.isPhoto {
            guard let record = tags.record(for: item.id) else { continue }
            result[record.category, default: 0] += 1
        }
        return result
    }

    private var analysedCount: Int {
        counts.values.reduce(0, +)
    }

    private var photoCount: Int {
        library.items.filter { $0.isPhoto }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if scanner.isScanning {
                        ScanProgressCard(title: "正在分析画面",
                                         detail: scanner.statusText,
                                         progress: scanner.progress) {
                            scanTask?.cancel()
                        }
                    } else if analysedCount == 0 {
                        introCard
                    } else {
                        overviewCard
                        categoryGrid
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("智能分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("继续分析未分类照片") {
                            startScan(rescanAll: false)
                        }
                        Button("重新分析全部照片") {
                            startScan(rescanAll: true)
                        }
                        Button("清除分类缓存", role: .destructive) {
                            tags.clear()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textPrimary)
                    }
                    .disabled(scanner.isScanning)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MarkedBar()
            }
        }
    }

    private var introCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.85))
            Text("用设备端智能给照片分类")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("系统视觉框架会离线识别画面内容，把照片归入人物、美食、风景、文档等类别，再按类别批量整理。全程不联网。")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)

            Toggle("包含 iCloud 照片（较慢、会耗流量）", isOn: $allowNetwork)
                .font(.system(size: 12))
                .tint(Theme.accent)
                .foregroundColor(Theme.textSecondary)

            Button("开始智能分析") {
                startScan(rescanAll: false)
            }
            .buttonStyle(FillButtonStyle())
            .disabled(photoCount == 0)

            Text("共 \(photoCount) 张照片待分析")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 14)
        .card()
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已分析 \(analysedCount) / \(photoCount) 张")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("点击分类查看，可批量加入相簿或标记清理")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Button("继续") {
                    startScan(rescanAll: false)
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.accent))
            }
            ProgressView(value: photoCount > 0 ? Double(analysedCount) / Double(photoCount) : 0)
                .tint(Theme.mint)
        }
        .card()
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(SmartCategories.all) { category in
                let count = counts[category.id] ?? 0
                if count > 0 {
                    NavigationLink {
                        SmartCategoryDetailView(category: category)
                    } label: {
                        CategoryCard(category: category, count: count)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startScan(rescanAll: Bool) {
        guard !scanner.isScanning else { return }
        scanTask = Task {
            await scanner.scan(library: library,
                               store: tags,
                               allowNetwork: allowNetwork,
                               rescanAll: rescanAll)
        }
    }
}

struct CategoryCard: View {
    let category: SmartCategory
    let count: Int

    init(category: SmartCategory, count: Int) {
        self.category = category
        self.count = count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Theme.accent)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
            }
            Text(category.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

struct SmartCategoryDetailView: View {
    let category: SmartCategory
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @EnvironmentObject private var tags: TagStore

    @State private var viewerItem: PhotoItem?
    @State private var showAlbumPicker = false

    init(category: SmartCategory) {
        self.category = category
    }

    private var items: [PhotoItem] {
        library.items
            .filter { $0.isPhoto && tags.record(for: $0.id)?.category == category.id }
            .sorted { $0.creationDate > $1.creationDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyStateView(icon: category.icon,
                               title: "这个分类还是空的",
                               message: "重新执行一次智能分析，可能会识别出更多照片。")
            } else {
                AssetGrid(items: items,
                          selectedIDs: selection.selected,
                          showSelection: selection.isSelecting,
                          onTap: handleTap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if selection.isSelecting {
                    BatchActionsBar(visibleIDs: items.map { $0.id })
                }
                MarkedBar()
            }
        }
        .navigationTitle("\(category.name) · \(items.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(selection.isSelecting ? "取消" : "选择") {
                        selection.isSelecting.toggle()
                        if !selection.isSelecting {
                            selection.selected.removeAll()
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)

                    Button {
                        showAlbumPicker = true
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 15))
                    }
                    .foregroundColor(Theme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerSheet(assetIDs: selection.isSelecting ? Array(selection.selected) : items.map { $0.id },
                             suggestedName: category.name)
        }
        .fullScreenCover(item: $viewerItem) { item in
            AssetViewer(item: item)
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
