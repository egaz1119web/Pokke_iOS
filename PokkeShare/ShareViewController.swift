import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 共有シート専用の受け口。Android の ShareReceiverActivity 相当。
///
/// コレクションが1つもあれば選択カードを出し、選ぶかスキップ（とりあえず追加する）してもらってから保存する。
/// コレクションが無ければ選ぶ意味が無いので、そのまま保存してトースト風の表示を一瞬出して閉じる。
/// 保存先は App Group の stash.json なので、アプリ本体は次のフォアグラウンド復帰時に
/// これを読み込んでマージする（OGPの取得もそのタイミングで走る）。
final class ShareViewController: UIViewController {

    private let toast = UILabel()
    private var pickerHosting: UIHostingController<SharePickerView>?

    /// 幕（黒35%）もカードもこちらで描くので、このビューコントローラの背景は透過にしてある。
    /// ところがOSがこれを載せている**外側の面**は不透明のままで、カードより上が
    /// 明るいグレーの帯として残る（幕の黒35%が systemGroupedBackground に乗った色）。
    ///
    /// 不透明な面は直上ではなくもっと祖先側にあるので、窓まで辿って透かす。
    /// 透けた先には共有元のアプリが出るので、幕が幕として見えるようになる。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        var ancestor = view.superview
        while let current = ancestor {
            current.backgroundColor = .clear
            current.isOpaque = false
            ancestor = current.superview
        }
        view.window?.backgroundColor = .clear
        view.window?.isOpaque = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setUpToast()

        Task { @MainActor in
            let text = await extractSharedText()
            StashRepository.shared.initialize()
            await handleShared(text)
        }
    }

    @MainActor
    private func handleShared(_ text: String?) async {
        guard let text, case let .ready(normalized) = StashRepository.shared.precheckAddLink(text) else {
            await finish(with: text.map { StashRepository.shared.addLink($0) } ?? .invalidUrl)
            return
        }

        let collections = StashRepository.shared.state.collections
        guard !collections.isEmpty else {
            await finish(with: StashRepository.shared.addLink(normalized))
            return
        }

        presentCollectionPicker(url: normalized, collections: collections)
    }

    private func presentCollectionPicker(url: String, collections: [StashCollection]) {
        let picker = SharePickerView(url: url, collections: collections) { [weak self] collectionId in
            guard let self else { return }
            self.dismissPicker()
            let result = StashRepository.shared.addLink(url, collectionId: collectionId)
            Task { @MainActor in await self.finish(with: result) }
        }
        let hosting = UIHostingController(rootView: picker)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        pickerHosting = hosting
    }

    private func dismissPicker() {
        guard let hosting = pickerHosting else { return }
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
        pickerHosting = nil
    }

    @MainActor
    private func finish(with result: AddLinkResult) async {
        // 上限の知らせは「次に何をすればいいか」まで書いてあるので、短いと読み切れない
        let (key, hold): (String, UInt64) = switch result {
        case .saved: ("share_saved", 900_000_000)
        case .limitReached: ("share_limit_reached", 1_800_000_000)
        case .invalidUrl: ("share_no_url", 900_000_000)
        }
        show(message: L.s(key))
        try? await Task.sleep(nanoseconds: hold)
        extensionContext?.completeRequest(returningItems: nil)
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
