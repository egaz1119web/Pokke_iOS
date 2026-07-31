import SwiftUI
import UIKit

/// 練習で共有するリンク。Pokke自身の紹介ページを使う。
/// App Store に出たらそちらのURLへ差し替えること（RELEASE.md）
private let practiceUrl = "https://pokke.op-sarada.workers.dev/"

/// 初回起動の案内。2枚組み。
///
/// 1枚のダイアログに手順を並べる形だと「共有シートのどこにPokkeがいるのか」が
/// 伝わらなかったため、読む→動く図で見る→そのまま1回やる、と流している。
/// いちど共有シートから保存するとOSが次からアプリの列の手前にPokkeを出すので、
/// 「1回やってもらう」ことには案内以上の実利がある。
///
/// 保存できたら祝いのページは挟まず、そのままホームへ抜ける（[onFinish] に
/// 保存された物を渡す）。実物の一覧が出てから、その上でスポットライトの案内を続ける。
struct OnboardingFlow: View {
    /// 案内の終わり。練習で保存できた場合はその1件を渡す
    let onFinish: (StashItem?) -> Void

    @ObservedObject private var repository = StashRepository.shared

    @State private var page = 0
    /// 共有シートを開いてから保存が見つかるまでの待ち状態
    @State private var waitingForShare = false
    /// 練習を始めた時点の保存済みID。ここに無いものが増えたら「保存された」と判る
    @State private var knownIds: Set<String> = []

    private let lastPage = 1

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, screenPadding)
                    .padding(.top, 8)

                pageBody
            }
        }
        // 保存はどの経路でも拾う。練習用ボタンからでも、他のアプリの共有からでもよい
        .onChange(of: repository.state.items.count) { _, _ in
            guard waitingForShare else { return }
            if let added = repository.state.items.first(where: { !knownIds.contains($0.id) }) {
                finishPractice(with: added)
            }
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        ZStack {
            PageDots(count: lastPage + 1, current: page)

            HStack {
                if page > 0 {
                    CircleIconButton(
                        icon: Lucide.chevronLeft,
                        accessibilityLabel: L.s("onboarding_back")
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) { page -= 1 }
                    }
                }
                Spacer(minLength: 0)
                // 最後の1枚は共有シートを開かないと先へ進まないので、どの枚でも抜け道を残す
                Button {
                    onFinish(nil)
                } label: {
                    Text(L.s("onboarding_skip"))
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(Palette.neutral700)
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 44)
    }

    // MARK: - 各ページ

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case 0:
            IntroPage(onNext: advance)
        default:
            // 別の練習ページは挟まない。動く図解を見たその場で共有シートを開く
            PinPokkePage(waiting: waitingForShare, onOpenShare: openShareSheet)
        }
    }

    private func advance() {
        withAnimation(.easeOut(duration: 0.2)) { page += 1 }
    }

    // MARK: - 練習

    private func openShareSheet() {
        guard let url = URL(string: practiceUrl), let presenter = topViewController() else { return }

        knownIds = Set(repository.state.items.map(\.id))
        waitingForShare = true

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPadでは吹き出しの根元が要る。画面下端の中央から出す
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { activityType, completed, _, _ in
            // 「Pokkeに保存」（共有拡張 com.egaz.stash.Share）を選んで完了したかどうか。
            // 拡張は同じURLの重複保存を弾いてファイルに書かないので、
            // 「新しいIDが増えたか」だけを見ていると、練習URLが保存済みの端末では
            // タップしても一生先へ進めない
            let viaPokke = completed && (activityType?.rawValue.hasPrefix("com.egaz.stash") ?? false)
            Task { await pollForSavedLink(sharedViaPokke: viaPokke, completed: completed) }
        }
        presenter.present(activity, animated: true)
    }

    /// 共有シートが閉じた直後はまだ拡張の書き込みが終わっていないことがある。
    /// 拡張は別プロセスで、保存されても通知は飛んでこないのでこちらから見に行く
    private func pollForSavedLink(sharedViaPokke: Bool, completed: Bool) async {
        // 選ばずに閉じた。押し直せる状態に戻すだけで、先へは進めない
        guard completed else {
            waitingForShare = false
            return
        }
        // 拡張は書き込みを終えてから完了を返すので、Pokke経由と分かっているなら長くは待たない
        for _ in 0..<(sharedViaPokke ? 5 : 25) {
            repository.reloadFromDisk()
            if let added = repository.state.items.first(where: { !knownIds.contains($0.id) }) {
                finishPractice(with: added)
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        // 新しいIDが増えていない＝以前に同じURLを保存済みで拡張が重複を弾いたケース。
        // 「Pokkeに保存」を選んだこと自体は確かなので、その既存の1件で先へ進む
        if sharedViaPokke,
           let normalized = StashRepository.normalizeUrl(practiceUrl),
           let existing = repository.state.items.first(where: { $0.url == normalized }) {
            finishPractice(with: existing)
            return
        }
        waitingForShare = false
    }

    private func finishPractice(with item: StashItem) {
        waitingForShare = false
        onFinish(item)
    }
}

// MARK: - 1枚目: 何のアプリか

private struct IntroPage: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(primaryTitle: L.s("onboarding_start"), onPrimary: onNext) {
            HStack(spacing: 8) {
                Text("Pokke")
                    .font(PokkeType.display)
                    .foregroundStyle(Palette.accent)
                LucideIconView(icon: Lucide.bookmark, size: 18, color: Palette.accent2)
                    .padding(.top, 4)
            }
            .padding(.top, 24)

            Text(L.s("onboarding_intro_title"))
                .font(PokkeType.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(L.s("onboarding_intro_lead"))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                BulletPoint(icon: Lucide.share, textKey: "onboarding_intro_point_share")
                BulletPoint(icon: Lucide.image, textKey: "onboarding_intro_point_preview")
            }
            .padding(.top, 26)
        }
    }
}

private struct BulletPoint: View {
    let icon: Lucide.Icon
    let textKey: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(
                icon: icon,
                tint: Palette.accent100,
                foreground: Palette.accent700,
                size: 44,
                iconSize: 20
            )
            Text(L.s(textKey))
                .font(PokkeType.bodyMedium)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 2枚目: Pokkeを先頭に置く（動く図解）

/// 「その他 → 編集 → ＋ → 並べ替え → 完了」でPokkeが共有シートの先頭に出る、
/// という一連の操作をミニ端末の中で自動再生する。静止画を並べる形だと
/// 「どの画面のどこを押すのか」が伝わらなかったための置き換え。
///
/// 下のボタンはそのまま本物の共有シートを開く。見た直後が一番手が動くので、
/// 間に練習用のページを挟まない。保存が拾えたら親が完了ページへ進める
private struct PinPokkePage: View {
    let waiting: Bool
    let onOpenShare: () -> Void

    var body: some View {
        OnboardingPage(
            primaryTitle: L.s("onboarding_try_it"),
            primaryIcon: Lucide.share,
            primaryEnabled: !waiting,
            onPrimary: onOpenShare
        ) {
            Text(L.s("onboarding_pin_title"))
                .font(PokkeType.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(L.s("onboarding_pin_lead"))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            // 共有シートを開いている間だけの案内。「Pokkeに保存」を選べば
            // この画面はひとりでに次へ進む。共有シートは画面の下半分を覆うので、
            // 隠れない上のここに置く
            if waiting {
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.accent)
                    Text(L.s("onboarding_waiting_lead"))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.accent800)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                        .fill(Palette.accent100)
                )
                .padding(.top, 14)
            }

            PinPokkeAnimation()
                .frame(maxWidth: .infinity)
                .padding(.top, waiting ? 14 : 20)
        }
    }
}

// MARK: - アニメーションの状態とタイムライン

/// ミニ端末の中のすべての可動部。各フィールドは絶対値で、
/// タイムラインの1ステップ＝このstructへの部分代入（パッチ）
private struct PinAnimState: Equatable {
    var cap = 0                                  // 現在のキャプション番号
    var fx: CGFloat = 120, fy: CGFloat = 275     // 指カーソル中心
    var fdown = false, fshow = false             // 押下中 / 表示
    var lift = false                             // Pokke行ドラッグ中（浮き）
    var app = false                              // アプリ管理画面表示
    var edit = false                             // 編集モード
    var added = false                            // よく使う項目に追加済み
    var first = false                            // 共有シートでPokkeが先頭
    var done = false                             // 完了チップ
    var pkTop: CGFloat = 108, msgTop: CGFloat = 18, mailTop: CGFloat = 52, candTop: CGFloat = 90
    var pressMore = false, pressEdit = false, pressPlus = false
}

/// 寸法。キャンバスは端末枠5pxの内側 218×330 で、座標はすべてこの内側基準の絶対値
private enum Pin {
    static let W: CGFloat = 218
    static let H: CGFloat = 330
    /// 共有シートの上端（それより上は「見ていたページ」）
    static let sheetTop: CGFloat = 140
    /// 共有シートのアイコン左端。左に10の余白、以降51刻み。5個目は見切れる
    static let iconSlotX: [CGFloat] = [10, 61, 112, 163, 214]
    /// アプリ管理画面のリスト原点（ヘッダー38 + 余白8）
    static let listTop: CGFloat = 46
    static let rowH: CGFloat = 30
}

/// 共有シートを自分好みに並べ替える操作の自動再生。
///
/// 実装は「状態パッチの列を1本のランナーで順に適用する」方式。
/// 各ステップが絶対値なので、シーンバーの頭出し（0..idxのパッチを畳み込む）や
/// ループが壊れない。アニメーション自体はビュー側の暗黙アニメーションに任せる。
private struct PinPokkeAnimation: View {

    private struct Step {
        let d: Int  // 次のステップまでのms
        let apply: (inout PinAnimState) -> Void
    }

    /// 1ループ≈13.2秒。capが変わるステップがシーンの頭出しポイント
    private static let timeline: [Step] = [
        Step(d: 500) { $0 = PinAnimState() },                                              // 0 ループ頭
        Step(d: 560) { $0.fshow = true; $0.fx = 185; $0.fy = 238 },                        // 指→「その他」
        Step(d: 200) { $0.fdown = true; $0.pressMore = true },
        Step(d: 420) { $0.fdown = false },
        Step(d: 700) { $0.app = true; $0.pressMore = false; $0.fshow = false; $0.cap = 1 }, // 4 アプリ画面push
        Step(d: 560) { $0.fshow = true; $0.fx = 193; $0.fy = 19 },                         // 指→「編集」
        Step(d: 200) { $0.fdown = true; $0.pressEdit = true },
        Step(d: 650) { $0.fdown = false; $0.pressEdit = false; $0.edit = true; $0.cap = 2 }, // 7 編集モード
        Step(d: 560) { $0.fx = 25; $0.fy = 169 },                                          // 指→Pokkeの「＋」
        Step(d: 200) { $0.fdown = true; $0.pressPlus = true },
        Step(d: 850) { $0.fdown = false; $0.pressPlus = false; $0.added = true
                       $0.pkTop = 86; $0.candTop = 124; $0.cap = 3 },                      // 10 追加
        Step(d: 560) { $0.fx = 193; $0.fy = 147 },                                         // 指→ハンドル
        Step(d: 420) { $0.fdown = true; $0.lift = true },
        Step(d: 560) { $0.pkTop = 48; $0.mailTop = 86; $0.fy = 109 },                      // メールを追い越す
        Step(d: 560) { $0.pkTop = 16; $0.msgTop = 52; $0.fy = 77 },                        // メッセージを追い越す
        Step(d: 360) { $0.pkTop = 18; $0.fy = 79 },                                        // 位置決め
        Step(d: 450) { $0.fdown = false; $0.lift = false; $0.cap = 4 },                    // 16 離す
        Step(d: 560) { $0.fx = 193; $0.fy = 19 },                                          // 指→「完了」
        Step(d: 200) { $0.fdown = true; $0.pressEdit = true },
        Step(d: 620) { $0.fdown = false; $0.pressEdit = false; $0.edit = false; $0.fshow = false },
        Step(d: 800) { $0.app = false; $0.first = true; $0.cap = 5 },                      // 20 共有シートへpop
        Step(d: 650) { $0.done = true },
        Step(d: 3000) { _ in },                                                            // ホールド→ループ
    ]

    /// cap n が最初に現れるステップ。シーンバーの頭出しに使う
    private static let capStart = [0, 4, 7, 10, 16, 20]

    /// iOSのシート系と同じ減速カーブ
    private static let ease = Animation.timingCurve(0.32, 0.72, 0.24, 1, duration: 0.5)

    @State private var st = PinAnimState()
    @State private var runner: Task<Void, Never>?

    private struct Ripple: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
    }

    @State private var ripples: [Ripple] = []
    @State private var rippleSeq = 0

    var body: some View {
        VStack(spacing: 12) {
            device
            caption
            sceneDots
        }
        .onAppear { start(at: 0) }
        .onDisappear { runner?.cancel() }
        .onChange(of: st.fdown) { _, down in
            if down { spawnRipple() }
        }
    }

    // MARK: 再生

    private func start(at step: Int) {
        runner?.cancel()
        // 頭出し: そこまでのパッチを畳み込めば、その時点の状態が正確に再現できる
        var folded = PinAnimState()
        for i in 0...step { Self.timeline[i].apply(&folded) }
        runner = Task { @MainActor in
            withAnimation(Self.ease) { st = folded }
            var i = step
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Self.timeline[i].d))
                guard !Task.isCancelled else { return }
                i = (i + 1) % Self.timeline.count
                let apply = Self.timeline[i].apply
                withAnimation(Self.ease) { apply(&st) }
            }
        }
    }

    private func spawnRipple() {
        rippleSeq += 1
        let ripple = Ripple(id: rippleSeq, x: st.fx, y: st.fy)
        ripples.append(ripple)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            ripples.removeAll { $0.id == ripple.id }
        }
    }

    // MARK: キャンバス

    private var device: some View {
        ZStack(alignment: .topLeading) {
            shareLayer
                // アプリ画面が乗っている間は少し左へ退く（iOSのpush遷移のパララックス）
                .offset(x: st.app ? -Pin.W * 0.14 : 0)
            appLayer
                .offset(x: st.app ? 0 : Pin.W * 1.01)
            if st.done {
                doneChip
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .frame(maxWidth: .infinity)
                    .offset(y: 96)
            }
            ForEach(ripples) { ripple in
                RippleRing().position(x: ripple.x, y: ripple.y)
            }
            finger
        }
        .frame(width: Pin.W, height: Pin.H)
        .background(Palette.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Palette.ink))
        // 見て分かる内容はキャプションが全部読み上げるので、絵は隠す
        .accessibilityHidden(true)
    }

    // MARK: 共有シートのレイヤー

    private var shareLayer: some View {
        ZStack(alignment: .topLeading) {
            // 後ろで見ていたページ。シートが前面だと分かるよう少し沈めておく
            Group {
                PlaceholderBar(width: 110).offset(x: 14, y: 24)
                PlaceholderBar(width: 176, light: true).offset(x: 14, y: 46)
                PlaceholderBar(width: 150, light: true).offset(x: 14, y: 64)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.neutral200)
                    .frame(width: 190, height: 40)
                    .offset(x: 14, y: 86)
            }
            Rectangle().fill(Palette.ink.opacity(0.15))
                .frame(width: Pin.W, height: Pin.sheetTop)
            sharePanel.offset(y: Pin.sheetTop)
        }
    }

    private var sharePanel: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(Palette.surface)
            Capsule().fill(Palette.neutral300)
                .frame(width: 34, height: 4)
                .offset(x: (Pin.W - 34) / 2, y: 7)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.neutral200)
                    .frame(width: 30, height: 30)
                    .overlay(LucideIconView(icon: Lucide.link, size: 14, color: Palette.neutral700))
                VStack(alignment: .leading, spacing: 5) {
                    PlaceholderBar(width: 92)
                    PlaceholderBar(width: 58, light: true)
                }
            }
            .offset(x: 12, y: 20)
            Rectangle().fill(Palette.divider).frame(width: Pin.W, height: 1).offset(y: 64)
            shareIcons.offset(y: 76)
        }
        .frame(width: Pin.W, height: Pin.H - Pin.sheetTop)
    }

    private var shareIcons: some View {
        ZStack(alignment: .topLeading) {
            shareSlot(label: "AirDrop", x: Pin.iconSlotX[0]) {
                ZStack {
                    Circle().fill(Palette.neutral300)
                    Circle().stroke(Palette.surface, lineWidth: 2).frame(width: 20, height: 20)
                }
            }
            // Pokke。先頭に置けたときだけAirDropの次に現れ、残りが1つずつ右へずれる
            shareSlot(label: L.s("onboarding_mock_pokke"), x: Pin.iconSlotX[1]) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.accent)
                    LucideIconView(icon: Lucide.bookmark, size: 18, color: .white)
                }
                .overlay {
                    if st.first { PulseRing() }
                }
            }
            .opacity(st.first ? 1 : 0)
            shareSlot(label: L.s("onboarding_mock_messages"), x: Pin.iconSlotX[st.first ? 2 : 1]) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.neutral300)
            }
            shareSlot(label: L.s("onboarding_mock_mail"), x: Pin.iconSlotX[st.first ? 3 : 2]) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.neutral300)
            }
            shareSlot(label: L.s("onboarding_mock_more"), x: Pin.iconSlotX[st.first ? 4 : 3]) {
                ZStack {
                    Circle().fill(st.pressMore ? Palette.neutral400 : Palette.neutral200)
                        .animation(.easeOut(duration: 0.2), value: st.pressMore)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Palette.neutral700).frame(width: 4, height: 4)
                        }
                    }
                }
            }
        }
    }

    private func shareSlot(
        label: String,
        x: CGFloat,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        VStack(spacing: 4) {
            icon().frame(width: 44, height: 44)
            // OSの画面を模しているので、書体もOSのもの（SF）をそのまま使う
            Text(label)
                .font(.system(size: 7.5))
                .foregroundStyle(Palette.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 48)
        .offset(x: x - 2)
    }

    // MARK: アプリ管理画面のレイヤー

    private var appLayer: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Palette.surface)
            PlaceholderBar(width: 70).offset(x: 12, y: 16)
            Text(L.s(st.edit ? "onboarding_mock_done" : "onboarding_mock_edit"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.accent700)
                .opacity(st.pressEdit ? 0.45 : 1)
                .animation(.easeOut(duration: 0.15), value: st.pressEdit)
                .position(x: 193, y: 19)
            Rectangle().fill(Palette.divider).frame(width: Pin.W, height: 1).offset(y: 38)
            appList.offset(y: Pin.listTop)
        }
        .frame(width: Pin.W, height: Pin.H)
        .shadow(color: Palette.ink.opacity(0.16), radius: 10, x: -4)
    }

    private var appList: some View {
        ZStack(alignment: .topLeading) {
            sectionLabel(L.s("onboarding_mock_favorites")).offset(x: 12, y: 2)
            sectionLabel(L.s("onboarding_mock_suggestions")).offset(x: 12, y: st.candTop + 2)
            appRow(L.s("onboarding_mock_messages"), favorite: true).offset(y: st.msgTop)
            appRow(L.s("onboarding_mock_mail"), favorite: true).offset(y: st.mailTop)
            appRow(L.s("onboarding_mock_notes"), favorite: false).offset(y: 176)
            appRow(L.s("onboarding_mock_reminders"), favorite: false).offset(y: 210)
            // Pokkeの行。追加でよく使う項目側に変わり、ドラッグ中は浮く
            appRow(L.s("onboarding_mock_pokke"), favorite: st.added, isPokke: true)
                .scaleEffect(st.lift ? 1.04 : 1)
                .shadow(
                    color: Palette.ink.opacity(st.lift ? 0.28 : 0),
                    radius: st.lift ? 9 : 0,
                    y: st.lift ? 8 : 0
                )
                .animation(.easeOut(duration: 0.3), value: st.lift)
                .zIndex(st.lift ? 5 : 1)
                .offset(y: st.pkTop)
        }
        .frame(width: Pin.W, height: Pin.H - Pin.listTop, alignment: .topLeading)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Palette.neutral600)
    }

    /// アプリ1行。編集モードのときだけ左のバッジと右のハンドル/トグルが見える
    private func appRow(_ name: String, favorite: Bool, isPokke: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.surface)
            EditBadge(minus: favorite, pressed: isPokke && st.pressPlus)
                .position(x: 25, y: 15)
                .opacity(st.edit ? 1 : 0)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isPokke ? Palette.accent : Palette.neutral300)
                if isPokke {
                    LucideIconView(icon: Lucide.bookmark, size: 11, color: .white)
                }
            }
            .frame(width: 20, height: 20)
            .position(x: 46, y: 15)
            Text(name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
                .position(x: 60 + 54, y: 15)
            Group {
                if favorite {
                    // 並べ替えのつまみ
                    VStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(Palette.neutral400).frame(width: 11, height: 1.6)
                        }
                    }
                } else if !isPokke {
                    // 候補側の行のトグル。飾りで、動かさない
                    ZStack(alignment: .trailing) {
                        Capsule().fill(Palette.accent2_600).frame(width: 18, height: 11)
                        Circle().fill(.white).frame(width: 9, height: 9).padding(.trailing, 1)
                    }
                }
            }
            .position(x: 193, y: 15)
            .opacity(st.edit ? 1 : 0)
        }
        .frame(width: Pin.W, height: Pin.rowH)
        .animation(.easeOut(duration: 0.3), value: st.edit)
    }

    // MARK: 完了チップ・指・キャプション

    private var doneChip: some View {
        HStack(spacing: 5) {
            LucideIconView(icon: Lucide.check, size: 11, color: .white)
            Text(L.s("onboarding_anim_done"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background(Capsule().fill(Palette.accent2_700))
        .softShadow(.md)
    }

    private var finger: some View {
        Circle()
            .fill(Palette.ink.opacity(0.30))
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
            .frame(width: 26, height: 26)
            .shadow(color: Palette.ink.opacity(0.25), radius: 4, y: 2)
            .scaleEffect(st.fdown ? 0.72 : 1)
            .animation(.easeOut(duration: 0.18), value: st.fdown)
            .position(x: st.fx, y: st.fy)
            .opacity(st.fshow ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: st.fshow)
    }

    private var caption: some View {
        ZStack {
            Text(L.s("onboarding_anim_cap\(st.cap)"))
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.neutral800)
                .multilineTextAlignment(.center)
                .id(st.cap)
                .transition(.opacity)
        }
        .frame(minHeight: 20)
        .animation(.easeOut(duration: 0.25), value: st.cap)
    }

    /// シーンの頭出し。眺めるだけでも成立するが、読み返したい場面に飛べるようにしておく
    private var sceneDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.capStart.count, id: \.self) { index in
                Button {
                    start(at: Self.capStart[index])
                } label: {
                    Capsule()
                        .fill(index == st.cap ? Palette.accent : Palette.neutral300)
                        .frame(width: index == st.cap ? 18 : 7, height: 7)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.s("onboarding_anim_cap\(index)"))
            }
        }
        .animation(.easeOut(duration: 0.2), value: st.cap)
    }
}

/// 編集モードの丸バッジ。よく使う項目側は赤の「−」、候補側は緑の「＋」
private struct EditBadge: View {
    let minus: Bool
    var pressed = false

    var body: some View {
        ZStack {
            Circle().fill(minus ? Palette.danger : Palette.accent2_600)
            Rectangle().fill(.white).frame(width: 7, height: 1.6)
            if !minus {
                Rectangle().fill(.white).frame(width: 1.6, height: 7)
            }
        }
        .frame(width: 13, height: 13)
        .opacity(pressed ? 0.45 : 1)
        .scaleEffect(pressed ? 0.85 : 1)
        .animation(.easeOut(duration: 0.15), value: pressed)
    }
}

/// タップ波紋。指の押下のたびに1回だけ広がって消える
private struct RippleRing: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Palette.ink.opacity(expanded ? 0 : 0.35), lineWidth: 2)
            .frame(width: 40, height: 40)
            .scaleEffect(expanded ? 1.32 : 0.62)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) { expanded = true }
            }
    }
}

/// 先頭に来たPokkeの回りで2回だけ脈打つ輪
private struct PulseRing: View {
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(Palette.accent.opacity(on ? 0 : 0.55), lineWidth: on ? 1 : 5)
            .scaleEffect(on ? 1.3 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).repeatCount(2, autoreverses: false)) {
                    on = true
                }
            }
    }
}

/// 図の中の「文字の代わり」の灰色の帯
private struct PlaceholderBar: View {
    let width: CGFloat
    var light = false

    var body: some View {
        Capsule()
            .fill(light ? Palette.neutral200 : Palette.neutral300)
            .frame(width: width, height: 7)
    }
}

// MARK: - ページの外枠

/// 全ページ共通の骨。本文はスクロールし、ボタンだけは常に下に置いておく
private struct OnboardingPage<Content: View>: View {
    let primaryTitle: String
    var primaryIcon: Lucide.Icon?
    var primaryEnabled = true
    let onPrimary: () -> Void
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, screenPadding)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                PrimaryButton(
                    title: primaryTitle,
                    icon: primaryIcon,
                    height: 54,
                    enabled: primaryEnabled,
                    action: onPrimary
                )
                if let secondaryTitle, let onSecondary {
                    Button(action: onSecondary) {
                        Text(secondaryTitle)
                            .font(PokkeType.labelMedium)
                            .foregroundStyle(Palette.neutral700)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}

/// 何枚のうちの何枚目か。初回案内とホームのスポットライトで共用する
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.accent : Palette.neutral300)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

// MARK: - ホームが空のときの案内

/// ホームが空のときに出す、共有からの保存を促す案内
struct ShareHintCard: View {
    let onShowGuide: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IconTile(
                icon: Lucide.inbox,
                tint: Palette.accent100,
                foreground: Palette.accent700,
                size: 64,
                iconSize: 28
            )
            Text(L.s("home_empty"))
                .font(PokkeType.bodyLarge)
                .foregroundStyle(Palette.ink)
            Text(L.s("home_empty_hint"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            OutlinedPillButton(title: L.s("onboarding_show_guide"), action: onShowGuide)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 40)
    }
}
