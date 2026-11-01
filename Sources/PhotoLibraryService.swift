import Foundation
import Combine
import Photos
import AVFoundation
import UIKit

@MainActor
final class PhotoLibraryService: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var items: [PhotoItem] = []
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var sizeIndexComplete = false
    @Published var isLoading = false
    @Published var isMeasuring = false
    @Published var sizeProgress: Double = 0
    @Published var errorMessage: String?
    @Published private(set) var libraryVersion = 0

    let imageManager = PHCachingImageManager()
    private var assetMap: [String: PHAsset] = [:]
    private let thumbnailCache = NSCache<NSString, UIImage>()

    init() {
        thumbnailCache.countLimit = 300
    }

    // MARK: - 授权

    var isAuthorized: Bool {
        switch status {
        case .authorized, .limited: return true
        default: return false
        }
    }

    var accessLevelText: String {
        switch status {
        case .authorized: return "完全访问"
        case .limited: return "仅可访问部分照片"
        case .denied: return "已拒绝"
        case .restricted: return "受系统限制"
        case .notDetermined: return "尚未授权"
        @unknown default: return "未知状态"
        }
    }

    func bootstrap() async {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            await requestPermission()
            return
        }
        if isAuthorized {
            await loadLibrary()
        }
    }

    func requestPermission() async {
        let result: PHAuthorizationStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
        status = result
        if result == .authorized || result == .limited {
            await loadLibrary()
        }
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    // MARK: - 读取资料库

    func loadLibrary() async {
        isLoading = true
        defer { isLoading = false }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let result = PHAsset.fetchAssets(with: options)
        var list: [PhotoItem] = []
        var map: [String: PHAsset] = [:]
        list.reserveCapacity(result.count)
        map.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            let item = PhotoItem(asset: asset)
            list.append(item)
            map[asset.localIdentifier] = asset
        }

        items = list
        assetMap = map
        sizes = sizes.filter { map[$0.key] != nil }
        sizeIndexComplete = false
        libraryVersion += 1
    }

    func asset(for id: String) -> PHAsset? {
        assetMap[id]
    }

    // MARK: - 文件体积

    static func fileSize(of asset: PHAsset) -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        for resource in resources {
            if let value = resource.value(forKey: "fileSize") as? Int64, value > 0 {
                return value
            }
            if let value = resource.value(forKey: "fileSize") as? NSNumber, value.int64Value > 0 {
                return value.int64Value
            }
        }
        return nil
    }

    func measureSizes(force: Bool = false, progress: ((Double) -> Void)? = nil) async {
        guard !isMeasuring else { return }
        isMeasuring = true
        sizeProgress = 0
        defer {
            isMeasuring = false
        }

        let targets = items
        var built = sizes
        var processed = 0

        for item in targets {
            if Task.isCancelled { return }
            if force || built[item.id] == nil {
                if let asset = assetMap[item.id], let value = Self.fileSize(of: asset) {
                    built[item.id] = value
                }
            }
            processed += 1
            if processed % 150 == 0 {
                let ratio = Double(processed) / Double(max(1, targets.count))
                sizes = built
                sizeProgress = ratio
                progress?(ratio)
                await Task.yield()
            }
        }

        sizes = built
        sizeProgress = 1
        sizeIndexComplete = true
        progress?(1)
    }

    var totalBytes: Int64 {
        sizes.values.reduce(Int64(0), +)
    }

    // MARK: - 图片与视频读取

    private func requestImage(asset: PHAsset, target: CGSize, contentMode: PHImageContentMode, mode: PHImageRequestOptionsDeliveryMode, allowNetwork: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = mode
            options.resizeMode = .fast
            options.version = .current
            options.isNetworkAccessAllowed = allowNetwork
            var resumed = false

            imageManager.requestImage(for: asset, targetSize: target, contentMode: contentMode, options: options) { image, info in
                guard !resumed else { return }

                if let info = info, let cancelled = info[PHImageCancelledKey] as? Bool, cancelled {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }
                if let info = info, let degraded = info[PHImageResultIsDegradedKey] as? Bool, degraded {
                    return
                }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    func thumbnail(for id: String, pixel: CGFloat = 200) async -> UIImage? {
        if let cached = thumbnailCache.object(forKey: id as NSString) {
            return cached
        }
        guard let asset = assetMap[id] else { return nil }
        let scale = UIScreen.main.scale
        let target = CGSize(width: pixel * scale, height: pixel * scale)
        guard let image = await requestImage(asset: asset,
                                             target: target,
                                             contentMode: .aspectFill,
                                             mode: .fastFormat,
                                             allowNetwork: true) else { return nil }
        thumbnailCache.setObject(image, forKey: id as NSString)
        return image
    }

    func image(for id: String, maxPixel: CGFloat) async -> UIImage? {
        guard let asset = assetMap[id] else { return nil }
        let target = CGSize(width: maxPixel, height: maxPixel)
        return await requestImage(asset: asset,
                                  target: target,
                                  contentMode: .aspectFit,
                                  mode: .highQualityFormat,
                                  allowNetwork: true)
    }

    func smallImage(for id: String, pixel: CGFloat, allowNetwork: Bool = false) async -> UIImage? {
        guard let asset = assetMap[id], asset.mediaType == .image else { return nil }
        let target = CGSize(width: pixel, height: pixel)
        return await requestImage(asset: asset,
                                  target: target,
                                  contentMode: .aspectFill,
                                  mode: .fastFormat,
                                  allowNetwork: allowNetwork)
    }

    func avAsset(for id: String) async -> AVAsset? {
        guard let asset = assetMap[id] else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            var resumed = false
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: avAsset)
            }
        }
    }

    // MARK: - 修改资料库

    func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count > 0 else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(fetch)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? libraryError("删除失败"))
                }
            })
        }

        removeItems(ids: ids)
    }

    func setFavorite(ids: [String], favorite: Bool) async throws {
        guard !ids.isEmpty else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count > 0 else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                fetch.enumerateObjects { asset, _, _ in
                    PHAssetChangeRequest(for: asset)?.isFavorite = favorite
                }
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? libraryError("修改收藏状态失败"))
                }
            })
        }

        let target = Set(ids)
        for index in items.indices where target.contains(items[index].id) {
            if let asset = assetMap[items[index].id] {
                items[index] = PhotoItem(asset: asset)
            }
        }
    }

    func albums() -> [PHAssetCollection] {
        var result: [PHAssetCollection] = []
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        fetch.enumerateObjects { collection, _, _ in
            if collection.canPerform(.addContent) {
                result.append(collection)
            }
        }
        return result
    }

    func createAlbum(named name: String, containing ids: [String]) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                request.addAssets(fetch)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? libraryError("创建相簿失败"))
                }
            })
        }
    }

    func add(ids: [String], to album: PHAssetCollection) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest(for: album)?.addAssets(fetch)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? libraryError("加入相簿失败"))
                }
            })
        }
    }

    private func removeItems(ids: [String]) {
        let target = Set(ids)
        items.removeAll { target.contains($0.id) }
        for id in ids {
            assetMap.removeValue(forKey: id)
            sizes.removeValue(forKey: id)
            thumbnailCache.removeObject(forKey: id as NSString)
        }
        libraryVersion += 1
    }
}

private func libraryError(_ text: String) -> NSError {
    NSError(domain: "com.troll.albumkeeper", code: -1,
            userInfo: [NSLocalizedDescriptionKey: text])
}
