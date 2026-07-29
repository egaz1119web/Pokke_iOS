import SwiftUI

/// 今すぐ呼べる、端末内AIの可否判定。
///
/// AndroidのAICore問い合わせと違い、`SystemLanguageModel.default.availability` は
/// 同期プロパティなので、Android版のような「判定が終わるまで入口を隠す」待ち時間は無い。
/// 画面が前面に来るたびに呼び直せば、設定でApple Intelligenceを有効にして
/// 戻ってきた場合にも追従できる。
func currentAiAvailability() -> AiAvailability { AiAssistant.availability() }

/// 入口を出すかどうか。端末非対応・OSが古い場合だけ恒久的に隠す。
/// 「設定でオフ」「モデル準備中」は入口自体は出し、聞いたときに理由を説明する
func showsAiEntryPoint(_ availability: AiAvailability) -> Bool {
    switch availability {
    case .deviceNotEligible, .unsupportedOSVersion: return false
    case .available, .appleIntelligenceNotEnabled, .modelNotReady: return true
    }
}

/// 保存したリンクについて端末内AIに聞くボトムシート。
///
/// `items` に渡した範囲だけが答えの根拠になる。コレクションを開いていれば
/// その中身、検索画面からなら全リンク、という具合に呼び出し側が決める。
struct AskAiSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scopeLabel: String
    let items: [StashItem]
    let suggestions: [String]
    var initialQuestion: String = ""

    @State private var question = ""
    // 生成し直すと数秒待たされるので、出た答えはそのまま保持する
    @State private var answer = ""
    @State private var thinking = false
    @State private var failure: AiFailure?
    // 答えの根拠にしたリンク。何を読んで答えたのかが見えないと、
    // 一部しか読んでいないことが「無かったことにされた」と受け取られる
    @State private var referenced: [StashItem] = []
    @FocusState private var questionFocused: Bool

    @State private var session: AnyObject?
    @State private var askTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHandle()

                HStack(alignment: .center, spacing: 12) {
                    IconTile(
                        icon: Lucide.sparkles,
                        tint: Palette.accent100,
                        foreground: Palette.accent700,
                        size: 44,
                        iconSize: 20
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("ai_sheet_title"))
                            .font(PokkeType.titleSmall)
                            .foregroundStyle(Palette.ink)
                        Text(scopeLabel)
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral600)
                    }
                }

                QuestionField(
                    question: $question,
                    focused: $questionFocused,
                    enabled: !thinking,
                    onSubmit: { ask(question) }
                )
                .padding(.top, 16)

                // 何を聞けるのか分からないと最初の一歩が出ないので、例を出しておく。
                // 答えが出たあとは邪魔になるので引っ込める
                if answer.isEmpty, !thinking, failure == nil, !suggestions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            SuggestionChip(text: suggestion) { ask(suggestion) }
                        }
                    }
                    .padding(.top, 12)
                }

                if thinking, answer.isEmpty {
                    Text(L.s("ai_thinking"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.neutral600)
                        .padding(.top, 20)
                }

                if !answer.isEmpty {
                    PokkeCard(padding: 16) {
                        Text(answer)
                            .font(PokkeType.bodyMedium)
                            .foregroundStyle(Palette.neutral800)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 16)
                }

                // 読んだリンクをそのまま出す。全部は読めていないので、
                // 何件のうちの何件かも一緒に見せて、足りなければ聞き直せるようにする
                if !answer.isEmpty, !referenced.isEmpty {
                    SectionLabel(text: referenced.count >= items.count
                        ? L.s("ai_referenced_all", referenced.count)
                        : L.s("ai_referenced_some", items.count, referenced.count))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    VStack(spacing: 6) {
                        ForEach(referenced) { item in
                            ReferencedLinkRow(item: item) { openLink(item) }
                        }
                    }
                }

                if let failure {
                    AiFailureBanner(failure: failure)
                        .padding(.top, 16)
                }

                Text(L.s("ai_disclaimer"))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                    .padding(.top, 18)

                Spacer(minLength: 26)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        .presentationDetents([.fraction(0.82)])
        .onAppear {
            question = initialQuestion
            if !initialQuestion.isEmpty { ask(initialQuestion) }
        }
        .onDisappear {
            askTask?.cancel()
            if #available(iOS 26.0, *) { (session as? AiSession)?.close() }
        }
    }

    private func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        guard #available(iOS 26.0, *) else {
            failure = .unavailable(currentAiAvailability())
            return
        }
        question = text
        answer = ""
        failure = nil
        thinking = true
        let selected = AiDigest.selectRelevant(items: items, question: text)
        referenced = selected
        let aiSession = (session as? AiSession) ?? {
            let created = AiSession()
            session = created
            return created
        }()
        askTask?.cancel()
        askTask = Task {
            let instruction = L.s("ai_instruction")
            let prompt = AiDigest.buildPrompt(
                instruction: instruction,
                context: AiDigest.buildContext(all: items, selected: selected, now: nowMillis()),
                question: text
            )
            do {
                for try await progress in aiSession.ask(prompt: prompt) {
                    if Task.isCancelled { return }
                    if case let .chunk(text) = progress { answer = text }
                }
                if Task.isCancelled { return }
                // 何も出てこなかった場合も「答えられなかった」として扱う
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    failure = .generationFailed
                }
            } catch {
                if Task.isCancelled { return }
                failure = (error as? AiError)?.failure ?? .generationFailed
            }
            thinking = false
        }
    }
}

/// 質問の入力欄。右端の丸ボタンで送る
private struct QuestionField: View {
    @Binding var question: String
    var focused: FocusState<Bool>.Binding
    let enabled: Bool
    let onSubmit: () -> Void

    private var canSend: Bool {
        enabled && !question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        PillField(focused: focused.wrappedValue, height: 54) {
            TextField(L.s("ai_question_placeholder"), text: $question)
                .font(PokkeType.labelLarge)
                .foregroundStyle(Palette.ink)
                .tint(Palette.accent)
                .submitLabel(.send)
                .focused(focused)
                .disabled(!enabled)
                .onSubmit(onSubmit)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSubmit) {
                ZStack {
                    Circle().fill(canSend ? Palette.accent : Palette.neutral300)
                    LucideIconView(icon: Lucide.arrowUp, size: 17, color: canSend ? .white : Palette.neutral600)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(L.s("ai_send"))
        }
    }
}

/// 質問の例。押すとそのまま聞きに行く
private struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.neutral700)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.95))
    }
}

/// 根拠にしたリンク1件。一覧の `ItemRow` より薄く小さくして、答えより目立たないようにする
private struct ReferencedLinkRow: View {
    let item: StashItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Thumbnail(item: item, size: 36, corner: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(L.s("item_meta", item.host, relativeTime(item.savedAt)))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.neutral600)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                LucideIconView(icon: Lucide.externalLink, size: 14, color: Palette.neutral500)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Corner.medium, style: .continuous).fill(Palette.surface.opacity(0.6)))
            .contentShape(RoundedRectangle(cornerRadius: Corner.medium, style: .continuous))
        }
        .buttonStyle(.pressScale(0.98))
    }
}

/// 失敗理由の案内。iOSは「取得中」の進捗が無い代わりに、設定への案内を出せる場合がある
private struct AiFailureBanner: View {
    let failure: AiFailure

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIconView(icon: Lucide.triangleAlert, size: 16, color: Palette.accent800)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.accent800)
                if case .unavailable(.appleIntelligenceNotEnabled) = failure {
                    Button(L.s("ai_open_settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.accent700)
                }
            }
        }
    }

    private var message: String {
        switch failure {
        case .unavailable(.deviceNotEligible), .unavailable(.unsupportedOSVersion):
            return L.s("ai_error_unsupported")
        case .unavailable(.appleIntelligenceNotEnabled):
            return L.s("ai_error_apple_intelligence_off")
        case .unavailable(.modelNotReady):
            return L.s("ai_error_model_not_ready")
        case .unavailable(.available), .generationFailed:
            return L.s("ai_error")
        }
    }
}

/// 一覧の上に置くAIの入口。対応端末でしか出さないので、押してから「使えません」に
/// なることは基本無い（設定オフ・準備中の案内はシートを開いてから出す）
struct AiAskBar: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                LucideIconView(icon: Lucide.sparkles, size: 17, color: Palette.accent700)
                Text(text)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.accent800)
                Spacer(minLength: 0)
                LucideIconView(icon: Lucide.chevronRight, size: 16, color: Palette.accent700)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Capsule().fill(Palette.accent100))
            .overlay(Capsule().stroke(Palette.accent300.opacity(0.6), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.985))
    }
}
