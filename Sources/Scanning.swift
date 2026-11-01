import Foundation
import Combine
import UIKit
import Vision
import Photos

// MARK: - 感知哈希

enum PerceptualHash {
    static let gridWidth = 9
    static let gridHeight = 8

    /// 差值哈希：把图片压成 9x8 灰度图，逐行比较相邻像素，得到 64 位指纹。
    static func dHash(_ image: UIImage) -> UInt64? {
        guard let cgImage = image.cgImage else { return nil }
        let width = gridWidth
        let height = gridHeight
        var bytes = [UInt8](repeating: 0, count: width * height)
        var drew = false

        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            drew = true
        }

        guard drew else { return nil }

        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                let left = bytes[row * width + column]
                let right = bytes[row * width + column + 1]
                hash <<= 1
                if left < right { hash |= 1 }
            }
        }
        return hash
    }

    static func distance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}

struct UnionFind {
    private var parent: [Int]

    init(_ count: Int) {
        parent = Array(0..<count)
    }

    func find(_ value: Int) -> Int {
        var current = value
        while parent[current] != current {
            current = parent[current]
        }
        return current
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let left = find(lhs)
        let right = find(rhs)
        if left != right {
            parent[right] = left
        }
    }
}

// MARK: - 重复扫描

enum DuplicateMode: String, CaseIterable, Identifiable {
    case exact = "精确重复"
    case similar = "相似照片"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .exact:
            return "尺寸与文件体积完全一致的项目，通常是同一张图被多次保存或导入。"
        case .similar:
            return "对画面做指纹比对，找出连拍、微调、重复保存等视觉高度接近的照片。"
        }
    }
}

struct DuplicateGroup: Identifiable {
    let id: String
    let title: String
    let items: [PhotoItem]
    let keeperID: String

    var extras: [PhotoItem] {
        items.filter { $0.id != keeperID }
    }

    var extraIDs: [String] {
        extras.map { $0.id }
    }
}

@MainActor
final class DuplicateScanner: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var lastMode: DuplicateMode?

    func reset() {
        groups = []
        progress = 0
        statusText = ""
        lastMode = nil
    }

    func scan(mode: DuplicateMode,
              library: PhotoLibraryService,
              includeScreenshots: Bool,
              allowNetwork: Bool) async {
        guard !isScanning else { return }
        isScanning = true
        groups = []
        progress = 0
        statusText = "准备中…"
        lastMode = mode

        switch mode {
        case .exact:
            await scanExact(library: library)
        case .similar:
            await scanSimilar(library: library,
                              includeScreenshots: includeScreenshots,
                              allowNetwork: allowNetwork)
        }

        if Task.isCancelled {
            statusText = "已取消"
        } else {
            progress = 1
        }
        isScanning = false
    }

    private func scanExact(library: PhotoLibraryService) async {
        if !library.sizeIndexComplete {
            statusText = "正在统计文件体积…"
            await library.measureSizes()
        }
        guard !Task.isCancelled else {
            isScanning = false
            return
        }

        statusText = "正在分组…"
        progress = 0.45

        var buckets: [String: [PhotoItem]] = [:]
        for item in library.items {
            guard let size = library.sizes[item.id], size > 0 else { continue }
            let dimensions = "\(item.pixelWidth)x\(item.pixelHeight)"
            let key: String
            if item.isVideo {
                key = "v|\(dimensions)|\(Int((item.duration * 10).rounded()))|\(size)"
            } else {
                key = "p|\(dimensions)|\(size)"
            }
            buckets[key, default: []].append(item)
        }

        var found: [DuplicateGroup] = []
        for (key, items) in buckets where items.count > 1 {
            guard !Task.isCancelled else { break }
            guard let keeper = Self.pickKeeper(from: items, sizes: library.sizes) else { continue }
            let size = library.sizes[items[0].id] ?? 0
            found.append(DuplicateGroup(id: key,
                                        title: "\(items.count) 项 · \(Fmt.bytes(size))",
                                        items: items,
                                        keeperID: keeper.id))
        }

        found.sort { $0.items.count > $1.items.count }
        groups = found
        progress = 1
        statusText = found.isEmpty ? "没有发现精确重复项" : "找到 \(found.count) 组重复"
    }

    private func scanSimilar(library: PhotoLibraryService,
                             includeScreenshots: Bool,
                             allowNetwork: Bool) async {
        statusText = "正在筛选照片…"
        progress = 0.02

        let targets = library.items.filter { item in
            guard item.isPhoto else { return false }
            if !includeScreenshots && item.isScreenshot { return false }
            return true
        }

        guard targets.count > 1 else {
            statusText = "照片数量太少，无需比对"
            return
        }

        var entries: [(item: PhotoItem, hash: UInt64)] = []
        entries.reserveCapacity(targets.count)

        for (index, item) in targets.enumerated() {
            if Task.isCancelled {
                isScanning = false
                return
            }
            if let image = await library.smallImage(for: item.id, pixel: 112, allowNetwork: allowNetwork),
               let hash = PerceptualHash.dHash(image) {
                entries.append((item: item, hash: hash))
            }
            if index % 20 == 0 {
                progress = 0.05 + 0.85 * Double(index) / Double(targets.count)
                statusText = "正在计算画面指纹 \(index + 1)/\(targets.count)"
                await Task.yield()
            }
        }

        guard !Task.isCancelled else {
            isScanning = false
            return
        }
        guard entries.count > 1 else {
            statusText = "没有获取到足够可分析的照片"
            return
        }

        statusText = "正在比对相似度…"
        progress = 0.93

        var unionFind = UnionFind(entries.count)
        var bands: [Int: [Int]] = [:]
        bands.reserveCapacity(entries.count * 4)

        for (index, entry) in entries.enumerated() {
            if Task.isCancelled { break }
            for band in 0..<8 {
                let byte = Int((entry.hash >> (band * 8)) & 0xFF)
                let key = band * 256 + byte
                let candidates = bands[key] ?? []
                for candidate in candidates {
                    let other = entries[candidate]
                    if PerceptualHash.distance(entry.hash, other.hash) <= 6
                        && Self.ratioIsClose(entry.item, other.item) {
                        unionFind.union(index, candidate)
                    }
                }
                bands[key, default: []].append(index)
            }
        }

        var components: [Int: [Int]] = [:]
        for index in 0..<entries.count {
            let root = unionFind.find(index)
            components[root, default: []].append(index)
        }

        var found: [DuplicateGroup] = []
        for (_, indexes) in components where indexes.count > 1 {
            let items = indexes.map { entries[$0].item }
            guard let keeper = Self.pickKeeper(from: items, sizes: library.sizes) else { continue }
            let identifier = items[0].id
            found.append(DuplicateGroup(id: identifier,
                                        title: "\(items.count) 张相似",
                                        items: items.sorted { $0.creationDate > $1.creationDate },
                                        keeperID: keeper.id))
        }

        found.sort { $0.items.count > $1.items.count }
        groups = found
        progress = 1
        statusText = found.isEmpty ? "没有发现相似照片" : "找到 \(found.count) 组相似照片"
    }

    private static func ratioIsClose(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        let tolerance = max(0.02, lhs.ratio * 0.04)
        return abs(lhs.ratio - rhs.ratio) <= tolerance
    }

    static func pickKeeper(from items: [PhotoItem], sizes: [String: Int64]) -> PhotoItem? {
        guard let first = items.first else { return nil }
        var keeper = first
        for item in items.dropFirst() where isBetter(item, than: keeper, sizes: sizes) {
            keeper = item
        }
        return keeper
    }

    private static func isBetter(_ candidate: PhotoItem, than current: PhotoItem, sizes: [String: Int64]) -> Bool {
        if candidate.pixelCount != current.pixelCount {
            return candidate.pixelCount > current.pixelCount
        }
        let candidateSize = sizes[candidate.id] ?? 0
        let currentSize = sizes[current.id] ?? 0
        if candidateSize != currentSize {
            return candidateSize > currentSize
        }
        if candidate.isFavorite != current.isFavorite {
            return candidate.isFavorite
        }
        return candidate.creationDate < current.creationDate
    }
}

// MARK: - 智能分类

struct SmartCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

enum SmartCategories {
    static let all: [SmartCategory] = [
        SmartCategory(id: "people", name: "人物", icon: "person.2.fill"),
        SmartCategory(id: "food", name: "美食", icon: "fork.knife"),
        SmartCategory(id: "nature", name: "风景自然", icon: "leaf.fill"),
        SmartCategory(id: "animal", name: "动物宠物", icon: "pawprint.fill"),
        SmartCategory(id: "building", name: "建筑城市", icon: "building.2.fill"),
        SmartCategory(id: "vehicle", name: "交通出行", icon: "car.fill"),
        SmartCategory(id: "document", name: "文档票据", icon: "doc.text.fill"),
        SmartCategory(id: "screenshot", name: "截图", icon: "photo.on.rectangle"),
        SmartCategory(id: "text", name: "文字白板", icon: "textformat"),
        SmartCategory(id: "night", name: "夜景星空", icon: "moon.stars.fill"),
        SmartCategory(id: "sport", name: "运动户外", icon: "figure.run"),
        SmartCategory(id: "indoor", name: "室内家居", icon: "sofa.fill"),
        SmartCategory(id: "tech", name: "数码设备", icon: "desktopcomputer"),
        SmartCategory(id: "art", name: "艺术演出", icon: "paintpalette.fill"),
        SmartCategory(id: "other", name: "其他", icon: "square.grid.2x2.fill")
    ]

    static func category(id: String) -> SmartCategory {
        all.first(where: { $0.id == id }) ?? all[all.count - 1]
    }

    private static let rules: [(id: String, keywords: [String])] = [
        ("food", ["food", "meal", "dish", "pizza", "burger", "sandwich", "sushi", "noodle",
                  "pasta", "cake", "dessert", "coffee", "tea", "drink", "beer", "wine",
                  "fruit", "vegetable", "restaurant", "kitchen", "cooking", "bread", "soup",
                  "meat", "seafood", "salad", "breakfast", "snack", "cookie", "candy"]),
        ("animal", ["cat", "dog", "animal", "bird", "pet", "fish", "horse", "insect",
                    "wildlife", "kitten", "puppy", "rabbit", "turtle", "lion", "tiger", "cow"]),
        ("people", ["person", "people", "portrait", "selfie", "bride", "groom", "child",
                    "baby", "crowd", "family", "smile", "man", "woman", "face", "student", "team"]),
        ("nature", ["landscape", "mountain", "beach", "sea", "ocean", "sky", "cloud", "sunset",
                    "sunrise", "forest", "tree", "flower", "garden", "snow", "river", "lake",
                    "waterfall", "field", "plant", "leaf", "desert", "island", "valley", "grass"]),
        ("building", ["building", "architecture", "house", "city", "street", "bridge", "tower",
                      "skyscraper", "church", "castle", "temple", "wall", "door", "window",
                      "roof", "stair", "monument", "museum"]),
        ("vehicle", ["car", "vehicle", "bicycle", "motorcycle", "airplane", "train", "boat",
                     "bus", "traffic", "road", "truck", "ship", "helicopter", "scooter"]),
        ("document", ["document", "paper", "receipt", "ticket", "book", "menu", "letter",
                      "form", "card", "poster", "brochure", "magazine", "newspaper", "certificate",
                      "passport", "invoice", "banknote"]),
        ("screenshot", ["screenshot", "web page", "website", "user interface", "app interface",
                        "computer monitor", "screen", "smartphone"]),
        ("text", ["text", "handwriting", "signature", "diagram", "chart", "slide", "presentation",
                  "whiteboard", "note", "notebook", "blackboard"]),
        ("night", ["night", "dark", "fireworks", "star", "moon", "aurora", "lightning", "candle"]),
        ("sport", ["sport", "football", "basketball", "soccer", "gym", "fitness", "hiking",
                   "skiing", "surfing", "swimming", "tennis", "yoga", "running", "cycling",
                   "skateboard", "climbing", "golf", "baseball"]),
        ("indoor", ["interior", "furniture", "sofa", "bed", "bathroom", "bedroom", "living room",
                    "office", "chair", "table", "lamp", "curtain", "carpet", "wardrobe"]),
        ("tech", ["computer", "laptop", "phone", "camera", "electronics", "gadget", "keyboard",
                  "monitor", "drone", "television", "headphone", "speaker", "robot", "console"]),
        ("art", ["painting", "art", "sculpture", "concert", "performance", "music", "stage",
                 "dance", "theater", "theatre", "festival", "parade", "costume", "graffiti"])
    ]

    static func analyze(image: UIImage) -> (category: String, confidence: Float, faces: Int)? {
        guard let cgImage = image.cgImage else { return nil }

        let classifyRequest = VNClassifyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let requests: [VNRequest] = [classifyRequest, faceRequest]

        do {
            try handler.perform(requests)
        } catch {
            return nil
        }

        let observations = (classifyRequest.results ?? []).prefix(12)
        var bestCategory = "other"
        var bestConfidence: Float = 0

        for observation in observations {
            let label = observation.identifier.lowercased()
            let confidence = observation.confidence
            guard confidence >= 0.12 else { continue }
            if let match = rules.first(where: { rule in
                rule.keywords.contains(where: { keyword in label.contains(keyword) })
            }) {
                bestCategory = match.id
                bestConfidence = confidence
                break
            }
        }

        let faces = faceRequest.results?.count ?? 0
        if faces > 0 && bestConfidence < 0.45 {
            bestCategory = "people"
            bestConfidence = max(bestConfidence, 0.45)
        }

        return (bestCategory, bestConfidence, faces)
    }

    /// 视觉分析比较耗时，放到后台线程执行，避免卡住界面。
    static func analyzeInBackground(image: UIImage) async -> (category: String, confidence: Float, faces: Int)? {
        await Task.detached(priority: .userInitiated) {
            analyze(image: image)
        }.value
    }
}

struct TagRecord: Codable {
    var category: String
    var confidence: Float
    var faces: Int
    var updated: Date
}

@MainActor
final class TagStore: ObservableObject {
    @Published private(set) var records: [String: TagRecord] = [:]

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("albumkeeper-tags.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: TagRecord].self, from: data) else { return }
        records = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func record(for id: String) -> TagRecord? {
        records[id]
    }

    func set(_ record: TagRecord, for id: String) {
        records[id] = record
    }

    /// 扫描结束后一次性提交，避免每分析一张就刷新整个界面。
    func replaceAll(_ newRecords: [String: TagRecord]) {
        records = newRecords
    }

    func clear() {
        records = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    var count: Int { records.count }
}

@MainActor
final class SmartScanner: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusText = ""

    func scan(library: PhotoLibraryService,
              store: TagStore,
              allowNetwork: Bool,
              rescanAll: Bool) async {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        statusText = "准备中…"

        let targets = library.items.filter { $0.isPhoto }
        var working = store.records
        var processed = 0

        for item in targets {
            if Task.isCancelled {
                store.replaceAll(working)
                store.save()
                isScanning = false
                return
            }
            processed += 1

            if !rescanAll && working[item.id] != nil {
                continue
            }

            if item.isScreenshot {
                working[item.id] = TagRecord(category: "screenshot", confidence: 1.0, faces: 0, updated: Date())
            } else if let image = await library.smallImage(for: item.id, pixel: 224, allowNetwork: allowNetwork),
                      let result = await SmartCategories.analyzeInBackground(image: image) {
                working[item.id] = TagRecord(category: result.category,
                                             confidence: result.confidence,
                                             faces: result.faces,
                                             updated: Date())
            }

            if processed % 40 == 0 {
                progress = Double(processed) / Double(max(1, targets.count))
                statusText = "正在分析 \(processed)/\(targets.count)"
                await Task.yield()
            }
        }

        store.replaceAll(working)
        store.save()
        progress = 1
        statusText = ""
        isScanning = false
    }
}
