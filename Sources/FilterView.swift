import SwiftUI

struct FilterView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @Binding var showSettings: Bool

    @State private var criteria = FilterCriteria()
    @State private var showFilterSheet = false
    @State private var viewerItem: PhotoItem?

    init(showSettings: Binding<Bool>) {
        _showSettings = showSettings
    }

    private var results: [PhotoItem] {
        criteria.apply(to: library.items, sizes: library.sizes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 6) {
                    filterStrip
                    content
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if selection.isSelecting {
                        BatchActionsBar(visibleIDs: results.map { $0.id })
                    }
                    MarkedBar()
                }
            }
            .navigationTitle("我的相册")
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
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(Theme.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(criteria: $criteria)
            }
            .fullScreenCover(item: $viewerItem) { item in
                AssetViewer(item: item)
            }
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showFilterSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                        Text("筛选条件")
                        if !criteria.isDefault {
                            Text("·\(criteria.activeChips.count)")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: 0x1B1206))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                }

                ForEach(criteria.activeChips.indices, id: \.self) { index in
                    Chip(text: criteria.activeChips[index])
                }

                Text("\(results.count) 项")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.accent)
                Text("正在读取相册…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            EmptyStateView(icon: "line.3.horizontal.decrease.circle",
                           title: "没有符合条件的项目",
                           message: "试着放宽筛选条件，或换一个时间范围。",
                           actionTitle: criteria.isDefault ? nil : "重置筛选",
                           action: { criteria = FilterCriteria() })
        } else {
            AssetGrid(items: results,
                      selectedIDs: selection.selected,
                      showSelection: selection.isSelecting,
                      onTap: handleTap)
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

// MARK: - 筛选面板

struct FilterSheet: View {
    @Binding var criteria: FilterCriteria
    @Environment(\.dismiss) private var dismiss

    init(criteria: Binding<FilterCriteria>) {
        _criteria = criteria
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("时间范围", selection: $criteria.datePreset) {
                        ForEach(DatePreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    if criteria.datePreset == .custom {
                        DatePicker("开始", selection: $criteria.customStart, displayedComponents: [.date])
                        DatePicker("结束", selection: $criteria.customEnd, displayedComponents: [.date])
                    }
                } header: {
                    Text("时间")
                }

                Section {
                    ForEach(MediaKind.allCases) { kind in
                        Button {
                            criteria.toggle(kind)
                        } label: {
                            HStack {
                                Text(kind.rawValue)
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                if criteria.kinds.contains(kind) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("类型（不选表示全部）")
                }

                Section {
                    Picker("体积", selection: $criteria.size) {
                        ForEach(SizeFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("画面比例", selection: $criteria.orientation) {
                        ForEach(OrientationFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                } header: {
                    Text("文件与画幅")
                }

                Section {
                    Picker("视频时长", selection: $criteria.duration) {
                        ForEach(DurationFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Toggle("只看收藏", isOn: $criteria.favoritesOnly)
                        .tint(Theme.accent)
                    Toggle("只看带定位的照片", isOn: $criteria.hasLocationOnly)
                        .tint(Theme.accent)
                } header: {
                    Text("其他条件")
                }

                Section {
                    Picker("排序", selection: $criteria.sort) {
                        ForEach(SortOption.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Button("重置全部条件") {
                        criteria = FilterCriteria()
                    }
                    .foregroundColor(Theme.danger)
                } header: {
                    Text("排序")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("筛选条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large])
    }
}
