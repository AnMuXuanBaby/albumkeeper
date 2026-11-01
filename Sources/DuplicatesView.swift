import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @StateObject private var scanner = DuplicateScanner()

    @State private var mode: DuplicateMode = .exact
    @State private var includeScreenshots = false
    @State private var allowNetwork = false
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    modePicker
                    optionRow
                    Text(mode.detail)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    if scanner.isScanning {
                        ScanProgressCard(title: "正在扫描",
                                         detail: scanner.statusText,
                                         progress: scanner.progress) {
                            scanTask?.cancel()
                        }
                    } else if scanner.groups.isEmpty {
                        startCard
                    } else {
                        summaryCard
                        ForEach(scanner.groups) { group in
                            NavigationLink {
                                DuplicateGroupDetailView(group: group)
                            } label: {
                                DuplicateGroupCard(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("重复与相似")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(scanner.groups.isEmpty ? "扫描" : "重新扫描") {
                        startScan()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .disabled(scanner.isScanning)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MarkedBar()
            }
        }
        .onChange(of: library.libraryVersion) { _ in
            if !scanner.isScanning {
                scanner.reset()
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(DuplicateMode.allCases) { item in
                Button {
                    guard !scanner.isScanning else { return }
                    mode = item
                    scanner.reset()
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mode == item ? Color(hex: 0x1B1206) : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(mode == item ? Theme.accent : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surface)
        .clipShape(Capsule())
    }

    private var optionRow: some View {
        HStack(spacing: 10) {
            if mode == .similar {
                Toggle("含截图", isOn: $includeScreenshots)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .font(.system(size: 12))
            }
            Toggle("含 iCloud", isOn: $allowNetwork)
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .font(.system(size: 12))
            Spacer()
        }
        .foregroundColor(Theme.textSecondary)
        .padding(.horizontal, 4)
    }

    private var startCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.8))
            Text("还没有扫描结果")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(mode == .exact
                 ? "精确重复比对需要先统计每个项目的文件体积，扫描会花一点时间。"
                 : "相似照片比对会为每张照片生成画面指纹，照片越多耗时越久。")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("开始扫描") {
                startScan()
            }
            .buttonStyle(FillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .card()
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(scanner.groups.count) 组 · \(totalExtras) 项可清理")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("预计可释放约 \(Fmt.bytes(estimatedSavings))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button("全部标记") {
                for group in scanner.groups {
                    selection.markedForDeletion.formUnion(group.extraIDs)
                }
            }
            .buttonStyle(GhostButtonStyle(tint: Theme.accent))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var totalExtras: Int {
        scanner.groups.reduce(0) { $0 + $1.extras.count }
    }

    private var estimatedSavings: Int64 {
        var total: Int64 = 0
        for group in scanner.groups {
            for extra in group.extras {
                total += library.sizes[extra.id] ?? 0
            }
        }
        return total
    }

    private func startScan() {
        guard !scanner.isScanning else { return }
        selection.markedForDeletion.removeAll()
        scanTask = Task {
            await scanner.scan(mode: mode,
                               library: library,
                               includeScreenshots: includeScreenshots,
                               allowNetwork: allowNetwork)
        }
    }
}

// MARK: - 分组卡片

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @EnvironmentObject private var library: PhotoLibraryService

    init(group: DuplicateGroup) {
        self.group = group
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("保留 1 · 可删 \(group.extras.count)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(spacing: 6) {
                ForEach(Array(group.items.prefix(5))) { item in
                    AssetThumbnail(item: item)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(item.id == group.keeperID ? Theme.mint : Color.clear, lineWidth: 2)
                        )
                }
                if group.items.count > 5 {
                    Text("+\(group.items.count - 5)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 40, height: 58)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text("预计释放 \(Fmt.bytes(group.extras.reduce(Int64(0)) { $0 + (library.sizes[$1.id] ?? 0) }))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("查看并保留 →")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
        }
        .card()
    }
}

// MARK: - 分组详情

struct DuplicateGroupDetailView: View {
    let group: DuplicateGroup
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @State private var keeperID: String
    @State private var viewerItem: PhotoItem?

    init(group: DuplicateGroup) {
        self.group = group
        _keeperID = State(initialValue: group.keeperID)
    }

    private var items: [PhotoItem] { group.items }
    private var extras: [PhotoItem] { items.filter { $0.id != keeperID } }

    var body: some View {
        VStack(spacing: 0) {
            keeperBar
            AssetGrid(items: items,
                      selectedIDs: selection.markedForDeletion,
                      showSelection: true,
                      keeperID: keeperID,
                      onTap: handleTap)
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button("标记其余 \(extras.count) 项") {
                        selection.markedForDeletion.formUnion(extras.map { $0.id })
                    }
                    .buttonStyle(GhostButtonStyle(tint: Theme.danger))

                    Spacer()

                    Button("取消本组标记") {
                        for item in extras {
                            selection.markedForDeletion.remove(item.id)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface)

                MarkedBar()
            }
        }
        .navigationTitle("重复组")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if let keeper = items.first(where: { $0.id == keeperID }) {
                        viewerItem = keeper
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 15))
                }
                .foregroundColor(Theme.textPrimary)
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            AssetViewer(item: item)
        }
        .onDisappear {
            selection.selected.removeAll()
        }
    }

    private var keeperBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.mint)
            Text("保留此张")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)

            Menu {
                ForEach(group.items) { item in
                    Button("\(Fmt.dateTime(item.creationDate)) · \(Fmt.sizeLabel(library.sizes[item.id]))") {
                        keeperID = item.id
                        selection.markedForDeletion.remove(item.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(keeperDateText)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.surface2)
                .clipShape(Capsule())
            }

            Spacer()

            Text("\(group.items.count) 项")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    private var keeperDateText: String {
        if let keeper = group.items.first(where: { $0.id == keeperID }) {
            return Fmt.dateTime(keeper.creationDate)
        }
        return "选择保留项"
    }

    private func handleTap(_ item: PhotoItem) {
        if item.id == keeperID {
            viewerItem = item
            return
        }
        selection.toggleMarked(item.id)
    }
}
