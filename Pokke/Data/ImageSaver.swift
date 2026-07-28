import Foundation
import Photos

/// サムネイル画像を端末の写真ライブラリ（アルバム「Pokke」）へ保存する。
///
/// Android版は MediaStore の Pictures/Pokke に書くが、iOSに同等の
/// 「アプリ専用フォルダ」は無いので、写真ライブラリ内に同名のアルバムを作る。
/// 追加のみなので必要な権限は `.addOnly`（Info.plist の
/// NSPhotoLibraryAddUsageDescription）だけで、閲覧の許可は求めない。
enum ImageSaver {

    private static let albumName = "Pokke"

    static func saveToPhotos(imageUrl: String, title: String) async -> Bool {
        guard let data = await download(imageUrl) else { return false }
        guard await requestAddOnlyAuthorization() else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                // アルバムが作れなくても、カメラロールには入っているので成功扱いにする
                if let album = albumChangeRequest(), let placeholder = request.placeholderForCreatedAsset {
                    album.addAssets([placeholder] as NSArray)
                }
            } completionHandler: { success, error in
                if let error { print("[ImageSaver] 保存に失敗: \(error.localizedDescription)") }
                continuation.resume(returning: success)
            }
        }
    }

    /// 既存の「Pokke」アルバムへの追加要求。無ければ作る
    private static func albumChangeRequest() -> PHAssetCollectionChangeRequest? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )
        if let album = existing.firstObject {
            return PHAssetCollectionChangeRequest(for: album)
        }
        return PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
    }

    private static func requestAddOnlyAuthorization() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .authorized || current == .limited { return true }
        guard current == .notDetermined else { return false }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return granted == .authorized || granted == .limited
    }

    private static func download(_ imageUrl: String) async -> Data? {
        guard let url = URL(string: imageUrl) else { return nil }
        var request = URLRequest(url: url)
        // 画像CDNもUAで出し分けることがあるため、取得時と同じUAを送る
        request.setValue(MetadataFetcher.userAgentFor(imageUrl), forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }
}
