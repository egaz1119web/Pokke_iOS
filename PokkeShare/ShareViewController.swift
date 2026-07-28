import UIKit
import UniformTypeIdentifiers

/// 共有シート専用の受け口。Android の ShareReceiverActivity 相当。
///
/// URLを保存してトースト風の表示を一瞬出したら、自分で完了して共有元アプリへ戻る。
/// 保存先は App Group の stash.json なので、アプリ本体は次のフォアグラウンド復帰時に
/// これを読み込んでマージする（OGPの取得もそのタイミングで走る）。
final class ShareViewController: UIViewController {

    private let toast = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setUpToast()

        Task { @MainActor in
            let text = await extractSharedText()
            StashRepository.shared.initialize()
            let saved = text.flatMap { StashRepository.shared.addLink($0) }
            show(message: L.s(saved != nil ? "share_saved" : "share_no_url"))
            try? await Task.sleep(nanoseconds: 900_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// 共有されたURL/テキストを取り出す。SafariはURL型、他アプリはプレーンテキストで渡してくる
    private func extractSharedText() async -> String? {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url.absoluteString
            }
        }
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return text
            }
        }
        return nil
    }

    private func setUpToast() {
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.textAlignment = .center
        toast.textColor = .white
        toast.font = .preferredFont(forTextStyle: .subheadline)
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        toast.layer.cornerRadius = 10
        toast.layer.masksToBounds = true
        toast.numberOfLines = 0
        toast.alpha = 0
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func show(message: String) {
        // 左右に余白を入れたいだけなので、前後を全角スペースで挟む簡易対応
        toast.text = "  \(message)  "
        UIView.animate(withDuration: 0.15) { self.toast.alpha = 1 }
    }
}
