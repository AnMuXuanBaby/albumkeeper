import SwiftUI
import AVKit
import Photos

// MARK: - 主题

enum Theme {
    static let bg = Color(hex: 0x0D0E11)
    static let surface = Color(hex: 0x171922)
    static let surface2 = Color(hex: 0x232633)
    static let accent = Color(hex: 0xF7A94C)
    static let mint = Color(hex: 0x5CE0C0)
    static let danger = Color(hex: 0xFF6B6B)
    static let textPrimary = Color(hex: 0xF3F4F6)
    static let textSecondary = Color(hex: 0x99A0AE)
    static let line = Color(hex: 0x2B2F3A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

// MARK: - 通用样式

struct FillButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var foreground: Color = Color(hex: 0x1B1206)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1.0))
            .foregroundColor(foreground)
            .clipShape(Capsule())
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.surface2.opacity(configuration.isPressed ? 0.6 : 1.0))
            .foregroundColor(tint)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
            .textCase(nil)
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Theme.accent

    init(text: String, tint: Color = Theme.accent) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = Theme.accent

    init(title: String, value: String, tint: Color = Theme.accent) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - 缩略图

struct AssetThumbnail: View {
    let item: PhotoItem
    @EnvironmentObject private var library: PhotoLibraryService
    @State private var image: UIImage?
    @State private var requested = false

    init(item: PhotoItem) {
        self.item = item
    }

    var body: some View {
        ZStack {
            Theme.surface2
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.isVideo ? "video" : "photo")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textSecondary.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: item.id) {
            guard !requested else { return }
            requested = true
            image = await library.thumbnail(for: item.id, pixel: 140)
        }
    }
}

struct AssetCell: View {
    let item: PhotoItem
    var selected: Bool = false
    var showSelectionMark: Bool = false
    var badge: String? = nil

    init(item: PhotoItem, selected: Bool = false, showSelectionMark: Bool = false, badge: String? = nil) {
        self.item = item
        self.selected = selected
        self.showSelectionMark = showSelectionMark
        self.badge = badge
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(AssetThumbnail(item: item))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2.5)
            )
            .overlay(alignment: .topTrailing) { durationBadge }
            .overlay(alignment: .bottomLeading) { mediaBadges }
            .overlay(alignment: .topLeading) { selectionMark }
            .overlay(alignment: .bottomTrailing) { keeperBadge }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if item.isVideo {
            Text(Fmt.duration(item.duration))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.62))
                .clipShape(Capsule())
                .padding(5)
        }
    }

    private var mediaBadges: some View {
        HStack(spacing: 4) {
            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.accent)
            }
            if item.isLive {
                Image(systemName: "livephoto")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
            if item.isScreenshot {
                Image(systemName: "iphone")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .padding(5)
    }

    @ViewBuilder
    private var selectionMark: some View {
        if showSelectionMark {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(selected ? Theme.accent : Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.45), radius: 3)
                .padding(6)
        }
    }

    @ViewBuilder
    private var keeperBadge: some View {
        if let badge = badge {
            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: 0x06231C))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.mint)
                .clipShape(Capsule())
                .padding(6)
        }
    }
}

// MARK: - 网格

struct AssetGrid: View {
    let items: [PhotoItem]
    var selectedIDs: Set<String> = []
    var showSelection = false
    var keeperID: String? = nil
    var onTap: (PhotoItem) -> Void

    init(items: [PhotoItem],
         selectedIDs: Set<String> = [],
         showSelection: Bool = false,
         keeperID: String? = nil,
         onTap: @escaping (PhotoItem) -> Void = { _ in }) {
        self.items = items
        self.selectedIDs = selectedIDs
        self.showSelection = showSelection
        self.keeperID = keeperID
        self.onTap = onTap
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 4, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(items) { item in
                    AssetCell(item: item,
                              selected: selectedIDs.contains(item.id),
                              showSelectionMark: showSelection,
                              badge: keeperID == item.id ? "保留" : nil)
                        .onTapGesture { onTap(item) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(icon: String,
         title: String,
         message: String,
         actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.8))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 28)
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(FillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - 扫描进度

struct ScanProgressCard: View {
    let title: String
    let detail: String
    let progress: Double
    let onCancel: () -> Void

    init(title: String, detail: String, progress: Double, onCancel: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.progress = progress
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.accent)
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(Theme.accent)
            HStack {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button("取消", action: onCancel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - 批量操作栏

struct BatchActionsBar: View {
    let visibleIDs: [String]
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @State private var showAlbumPicker = false
    @State private var busy = false

    init(visibleIDs: [String]) {
        self.visibleIDs = visibleIDs
    }

    var body: some View {
        HStack(spacing: 0) {
            actionButton("全选", icon: "checkmark.circle") {
                selection.selectAll(visibleIDs)
            }
            actionButton("收藏", icon: "heart") {
                setFavorite(true)
            }
            actionButton("相簿", icon: "rectangle.stack.badge.plus") {
                showAlbumPicker = true
            }
            actionButton("删除", icon: "trash", tint: Theme.danger) {
                selection.markSelectedForDeletion()
            }
            actionButton("完成", icon: "xmark") {
                selection.clearSelection()
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
        .disabled(busy)
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerSheet(assetIDs: Array(selection.selected))
        }
    }

    private func actionButton(_ title: String, icon: String, tint: Color = Theme.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setFavorite(_ value: Bool) {
        let ids = Array(selection.selected)
        guard !ids.isEmpty else { return }
        busy = true
        Task {
            do {
                try await library.setFavorite(ids: ids, favorite: value)
            } catch {
                library.errorMessage = error.localizedDescription
            }
            busy = false
            selection.clearSelection()
        }
    }
}

// MARK: - 待删除提示条

struct MarkedBar: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @State private var confirmDelete = false
    @State private var working = false

    var body: some View {
        Group {
            if selection.markedForDeletion.isEmpty || working {
                EmptyView()
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已标记 \(selection.markedForDeletion.count) 项待清理")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("删除后可在系统「最近删除」中 30 天内恢复")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Button("确认") {
                        confirmDelete = true
                    }
                    .buttonStyle(FillButtonStyle(tint: Theme.danger, foreground: .white))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.surface)
                .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
            }
        }
        .confirmationDialog("确认清理 \(selection.markedForDeletion.count) 项？",
                            isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("移入最近删除", role: .destructive) {
                performDelete()
            }
            Button("取消标记", role: .destructive) {
                selection.markedForDeletion.removeAll()
            }
            Button("再想想", role: .cancel) { }
        } message: {
            Text("这些项目会被移入系统相簿的「最近删除」，30 天内可以恢复。")
        }
    }

    private func performDelete() {
        let ids = Array(selection.markedForDeletion)
        guard !ids.isEmpty else { return }
        working = true
        Task {
            do {
                try await library.delete(ids: ids)
                selection.markedForDeletion.removeAll()
            } catch {
                library.errorMessage = error.localizedDescription
            }
            working = false
        }
    }
}

// MARK: - 相簿选择

struct AlbumPickerSheet: View {
    let assetIDs: [String]
    var suggestedName: String = ""
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PHAssetCollection] = []
    @State private var newName: String = ""
    @State private var busy = false

    init(assetIDs: [String], suggestedName: String = "") {
        self.assetIDs = assetIDs
        self.suggestedName = suggestedName
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("相簿名称", text: $newName)
                            .foregroundColor(Theme.textPrimary)
                        Button("创建") {
                            createAlbum()
                        }
                        .disabled(trimmedName.isEmpty || busy)
                        .foregroundColor(Theme.accent)
                    }
                } header: {
                    Text("新建相簿（\(assetIDs.count) 项）")
                }

                Section {
                    if albums.isEmpty {
                        Text("没有可写入的相簿")
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        ForEach(albums, id: \.localIdentifier) { album in
                            Button {
                                add(to: album)
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.stack")
                                        .foregroundColor(Theme.accent)
                                    Text(album.localizedTitle ?? "未命名相簿")
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Text("\(PHAsset.fetchAssets(in: album, options: nil).count) 项")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                            .disabled(busy)
                        }
                    }
                } header: {
                    Text("加入已有相簿")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("加入相簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                albums = library.albums()
                if newName.isEmpty { newName = suggestedName }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createAlbum() {
        guard !trimmedName.isEmpty else { return }
        busy = true
        Task {
            do {
                try await library.createAlbum(named: trimmedName, containing: assetIDs)
                dismiss()
            } catch {
                library.errorMessage = error.localizedDescription
                busy = false
            }
        }
    }

    private func add(to album: PHAssetCollection) {
        busy = true
        Task {
            do {
                try await library.add(ids: assetIDs, to: album)
                dismiss()
            } catch {
                library.errorMessage = error.localizedDescription
                busy = false
            }
        }
    }
}

// MARK: - 大图/视频查看

struct AssetViewer: View {
    let item: PhotoItem
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var selection: SelectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var failed = false

    init(item: PhotoItem) {
        self.item = item
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item.isVideo {
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if failed {
                    Text("无法加载视频")
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image = image {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
            } else if failed {
                Text("无法加载照片")
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    Button {
                        selection.toggleMarked(item.id)
                    } label: {
                        Image(systemName: selection.markedForDeletion.contains(item.id) ? "trash.fill" : "trash")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 3) {
                    Text(Fmt.dateTime(item.creationDate))
                        .font(.system(size: 13, weight: .medium))
                    Text("\(item.pixelWidth)×\(item.pixelHeight) · \(Fmt.sizeLabel(library.sizes[item.id]))")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.bottom, 28)
            }
        }
        .task {
            await load()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func load() async {
        if item.isVideo {
            guard let asset = await library.avAsset(for: item.id) else {
                failed = true
                return
            }
            if player == nil {
                let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                player = newPlayer
                newPlayer.play()
            }
        } else {
            image = await library.image(for: item.id, maxPixel: 1800)
            if image == nil { failed = true }
        }
    }
}
