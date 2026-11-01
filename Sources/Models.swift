import Foundation
import Photos
import CoreLocation

// MARK: - 单个相册条目

struct PhotoItem: Identifiable {
    let id: String
    let mediaType: PHAssetMediaType
    let subtype: PHAssetMediaSubtype
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let isFavorite: Bool
    let burstIdentifier: String?
    let latitude: Double?
    let longitude: Double?

    var isVideo: Bool { mediaType == .video }
    var isPhoto: Bool { mediaType == .image }
    var isLive: Bool { subtype.contains(.photoLive) }
    var isScreenshot: Bool { subtype.contains(.photoScreenshot) }
    var isPanorama: Bool { subtype.contains(.photoPanorama) }
    var isBurst: Bool { burstIdentifier != nil }
    var hasLocation: Bool { latitude != nil }
    var pixelCount: Int { max(1, pixelWidth * pixelHeight) }
    var ratio: Double { pixelHeight > 0 ? Double(pixelWidth) / Double(pixelHeight) : 1.0 }

    var orientationLabel: String {
        if abs(ratio - 1.0) < 0.03 { return "方图" }
        return ratio > 1.0 ? "横图" : "竖图"
    }
}

extension PhotoItem {
    init(asset: PHAsset) {
        self.init(id: asset.localIdentifier,
                  mediaType: asset.mediaType,
                  subtype: asset.mediaSubtypes,
                  creationDate: asset.creationDate ?? Date.distantPast,
                  pixelWidth: asset.pixelWidth,
                  pixelHeight: asset.pixelHeight,
                  duration: asset.duration,
                  isFavorite: asset.isFavorite,
                  burstIdentifier: asset.burstIdentifier,
                  latitude: asset.location?.coordinate.latitude,
                  longitude: asset.location?.coordinate.longitude)
    }
}

// MARK: - 筛选项

enum MediaKind: String, CaseIterable, Identifiable {
    case photo = "照片"
    case video = "视频"
    case live = "实况"
    case screenshot = "截图"
    case burst = "连拍"
    case panorama = "全景"

    var id: String { rawValue }
}

enum DatePreset: String, CaseIterable, Identifiable {
    case all = "全部时间"
    case today = "今天"
    case week = "近 7 天"
    case month = "近 30 天"
    case year = "今年"
    case custom = "自定义"

    var id: String { rawValue }
}

enum SizeFilter: String, CaseIterable, Identifiable {
    case any = "不限体积"
    case small = "小于 1 MB"
    case medium = "1 – 5 MB"
    case large = "5 – 20 MB"
    case huge = "大于 20 MB"

    var id: String { rawValue }
}

enum DurationFilter: String, CaseIterable, Identifiable {
    case any = "不限时长"
    case short = "短视频（< 10 秒）"
    case medium = "10 秒 – 1 分钟"
    case long = "1 – 5 分钟"
    case veryLong = "长于 5 分钟"

    var id: String { rawValue }
}

enum OrientationFilter: String, CaseIterable, Identifiable {
    case any = "全部比例"
    case portrait = "竖图"
    case landscape = "横图"
    case square = "方图"

    var id: String { rawValue }
}

enum SortOption: String, CaseIterable, Identifiable {
    case newest = "最新优先"
    case oldest = "最早优先"
    case largest = "体积最大"
    case smallest = "体积最小"
    case longest = "时长最长"

    var id: String { rawValue }
}

// MARK: - 筛选条件

struct FilterCriteria: Equatable {
    var datePreset: DatePreset = .all
    var customStart: Date = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
    var customEnd: Date = Date()

    var kinds: Set<MediaKind> = []
    var size: SizeFilter = .any
    var duration: DurationFilter = .any
    var orientation: OrientationFilter = .any

    var favoritesOnly: Bool = false
    var hasLocationOnly: Bool = false
    var sort: SortOption = .newest

    var isDefault: Bool {
        datePreset == .all && kinds.isEmpty && size == .any && duration == .any
            && orientation == .any && !favoritesOnly && !hasLocationOnly && sort == .newest
    }

    var activeChips: [String] {
        var chips: [String] = []
        if datePreset != .all { chips.append(datePreset.rawValue) }
        if !kinds.isEmpty {
            chips.append(kinds.map { $0.rawValue }.sorted().joined(separator: "·"))
        }
        if size != .any { chips.append(size.rawValue) }
        if duration != .any { chips.append(duration.rawValue) }
        if orientation != .any { chips.append(orientation.rawValue) }
        if favoritesOnly { chips.append("仅收藏") }
        if hasLocationOnly { chips.append("有定位") }
        if sort != .newest { chips.append(sort.rawValue) }
        return chips
    }

    mutating func toggle(_ kind: MediaKind) {
        if kinds.contains(kind) {
            kinds.remove(kind)
        } else {
            kinds.insert(kind)
        }
    }

    func apply(to list: [PhotoItem], sizes: [String: Int64]) -> [PhotoItem] {
        let filtered = list.filter { matches($0, size: sizes[$0.id]) }
        return sortList(filtered, sizes: sizes)
    }

    private var activeDateRange: (Date, Date)? {
        let calendar = Calendar.current
        let now = Date()
        switch datePreset {
        case .all:
            return nil
        case .today:
            return (calendar.startOfDay(for: now), now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .month:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            return (start, now)
        case .custom:
            return (customStart, customEnd)
        }
    }

    private func matches(_ item: PhotoItem, size value: Int64?) -> Bool {
        if let range = activeDateRange {
            if item.creationDate < range.0 || item.creationDate > range.1 { return false }
        }

        if !kinds.isEmpty {
            var hit = false
            for kind in kinds {
                switch kind {
                case .photo:
                    if item.isPhoto { hit = true }
                case .video:
                    if item.isVideo { hit = true }
                case .live:
                    if item.isLive { hit = true }
                case .screenshot:
                    if item.isScreenshot { hit = true }
                case .burst:
                    if item.isBurst { hit = true }
                case .panorama:
                    if item.isPanorama { hit = true }
                }
            }
            if !hit { return false }
        }

        if favoritesOnly && !item.isFavorite { return false }
        if hasLocationOnly && !item.hasLocation { return false }

        if !matchesSize(value) { return false }
        if !matchesDuration(item) { return false }
        if !matchesOrientation(item) { return false }

        return true
    }

    private func matchesSize(_ value: Int64?) -> Bool {
        switch size {
        case .any:
            return true
        case .small:
            guard let value = value else { return false }
            return value < 1_000_000
        case .medium:
            guard let value = value else { return false }
            return value >= 1_000_000 && value < 5_000_000
        case .large:
            guard let value = value else { return false }
            return value >= 5_000_000 && value < 20_000_000
        case .huge:
            guard let value = value else { return false }
            return value >= 20_000_000
        }
    }

    private func matchesDuration(_ item: PhotoItem) -> Bool {
        switch duration {
        case .any:
            return true
        case .short:
            return item.isVideo && item.duration < 10
        case .medium:
            return item.isVideo && item.duration >= 10 && item.duration < 60
        case .long:
            return item.isVideo && item.duration >= 60 && item.duration < 300
        case .veryLong:
            return item.isVideo && item.duration >= 300
        }
    }

    private func matchesOrientation(_ item: PhotoItem) -> Bool {
        switch orientation {
        case .any:
            return true
        case .portrait:
            return item.ratio < 0.97
        case .landscape:
            return item.ratio > 1.03
        case .square:
            return abs(item.ratio - 1.0) <= 0.03
        }
    }

    private func sortList(_ list: [PhotoItem], sizes: [String: Int64]) -> [PhotoItem] {
        switch sort {
        case .newest:
            return list.sorted { $0.creationDate > $1.creationDate }
        case .oldest:
            return list.sorted { $0.creationDate < $1.creationDate }
        case .largest:
            return list.sorted { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) }
        case .smallest:
            return list.sorted { (sizes[$0.id] ?? 0) < (sizes[$1.id] ?? 0) }
        case .longest:
            return list.sorted { $0.duration > $1.duration }
        }
    }
}

// MARK: - 格式化

enum Fmt {
    static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "—" }
        return bytesFormatter.string(fromByteCount: value)
    }

    static func sizeLabel(_ value: Int64?) -> String {
        guard let value = value else { return "—" }
        return bytes(value)
    }

    static func duration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func date(_ value: Date) -> String {
        dayFormatter.string(from: value)
    }

    static func dateTime(_ value: Date) -> String {
        minuteFormatter.string(from: value)
    }
}
