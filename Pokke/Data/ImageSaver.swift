import Foundation
import Photos
import UniformTypeIdentifiers

/// サムネイル画像を端末の写真ライブラリへ保存する。
///
/// Android版は MediaStore の Pictures/Pokke に書くが、iOSに同等の
/// 「アプリ専用フォルダ」は無いので、写真ライブラリへそのまま追加する。
/// 必要な権限は `.addOnly`（Info.plist の NSPhotoLibraryAddUsageDescription）だけで、
/// 閲覧の許可は求めない。
///
/// **アルバム「Pokke」は作らない**。アルバムを作る・探すには写真ライブラリの
/// 読み取りと変更（`NSPhotoLibraryUsageDescription`）が要り、追加専用の許可しか
/// 宣言していない状態でそのAPIに触るとiOSがアプリを強制終了させる。
/// 追加専用のまま済ませられる範囲に留め、写真アプリ側の「最近の項目」に入る形にした。
enum ImageSaver {

    static func saveToPhotos(imageUrl: String, title: String) async -> Bool {
        guard let downloaded = await download(imageUrl) else { return false }
        guard await requestAddOnlyAuthorization() else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                // 形式（UTI）を渡さないと、JPEG以外（WebPなど）でPhotosが
                // データを読める画像だと認識できず、保存が黙って失敗することがある
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = downloaded.uti
                request.addResource(with: .photo, data: downloaded.data, options: options)
            } completionHandler: { success, error in
                if let error { print("[ImageSaver] 保存に失敗: \(error.localizedDescription)") }
                continuation.resume(returning: success)
            }
        }
    }

    private static func requestAddOnlyAuthorization() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .authorized || current == .limited { return true }
        guard current == .notDetermined else { return false }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return granted == .authorized || granted == .limited
    }

    private static func download(_ imageUrl: String) async -> (data: Data, uti: String?)? {
        guard let url = URL(string: imageUrl) else { return nil }
        var request = URLRequest(url: url)
        // 画像CDNもUAで出し分けることがあるため、取得時と同じUAを送る
        request.setValue(MetadataFetcher.userAgentFor(imageUrl), forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return (data, uti(response: http, url: url))
    }

    /// レスポンスのContent-Type、無ければURLの拡張子からUTIを推測する。
    /// どちらも当たらなければnilのままPhotos側の推測に任せる
    private static func uti(response: HTTPURLResponse, url: URL) -> String? {
        if let mimeType = response.mimeType, let type = UTType(mimeType: mimeType) {
            return type.identifier
        }
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return type.identifier
        }
        return nil
    }
}
