import FoundationModels
import Foundation

/// 端末内AI（Apple Foundation Models）が使えるかの理由。
///
/// Androidの `AiFailure.UNSUPPORTED` 相当だが、iOSでは3つに分かれる。
/// Androidと違い、アプリ側からモデルをダウンロードさせる仕組みは無い
/// （Apple Intelligence自体をOS設定で有効にした際にOSが用意する）ため、
/// 「取得中」の進捗を見せるUIは存在しない。
enum AiAvailability: Equatable {
    /// 使える
    case available
    /// この端末はApple Intelligence非対応。恒久的なので入口ごと隠す
    case deviceNotEligible
    /// 端末は対応しているが、設定でApple Intelligenceが有効になっていない
    case appleIntelligenceNotEnabled
    /// モデルの準備がまだ済んでいない（一時的。少し待てば使える）
    case modelNotReady
    /// iOS26未満
    case unsupportedOSVersion
}

enum AiFailure: Equatable {
    case unavailable(AiAvailability)
    case generationFailed
}

struct AiError: Error {
    let failure: AiFailure
}

/// 生成中にシートへ届くもの。Foundation Modelsのストリーミングは
/// **累積スナップショット**（差分ではない）なので、届いた文字列でそのまま置き換える
enum AiProgress {
    case chunk(String)
}

/// 端末内AIが使えるかの判定。
///
/// SDKに触れるのはこのファイル（と `AiSession`）だけ。
/// `availability()` はどのiOSバージョンからでも安全に呼べる
/// （内部で `#available` に分岐するので、呼び出し側でバージョンガードは不要）。
enum AiAssistant {

    static func availability() -> AiAvailability {
        guard #available(iOS 26.0, *) else { return .unsupportedOSVersion }
        return currentAvailability()
    }

    @available(iOS 26.0, *)
    private static func currentAvailability() -> AiAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            // 将来追加されるかもしれない理由。恒久扱いにはせず、待てば直る可能性を残す
            return .modelNotReady
        }
    }
}

/// タグ提案の構造化出力。既存タグ語彙の再利用を優先させるプロンプトと組み合わせる
@available(iOS 26.0, *)
@Generable
struct TagSuggestions {
    @Guide(description: "Up to 4 short tags for this link. Lowercase, 1-2 words each, no hashtag symbol.", .count(0...4))
    let tags: [String]
}

/// 1回のシート表示ぶんの推論エンジン。
///
/// エンジンの確保はそれなりに重いので、シートを開いている間は使い回し、
/// 閉じるときに `close()` で必ず解放する。
@available(iOS 26.0, *)
final class AiSession {

    private var session: LanguageModelSession?

    private func engine() -> LanguageModelSession {
        if let session { return session }
        let created = LanguageModelSession()
        session = created
        return created
    }

    /// 質問を投げ、生成された文字列を届いた順（累積スナップショット）に流す
    func ask(prompt: String) -> AsyncThrowingStream<AiProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let options = GenerationOptions(temperature: 0.2)
                    let stream = engine().streamResponse(to: prompt, options: options)
                    for try await partial in stream {
                        continuation.yield(.chunk(partial.content))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AiError(failure: .generationFailed))
                }
            }
        }
    }

    /// タグ候補を構造化出力で受け取る
    func suggestTags(prompt: String) async throws -> [String] {
        let options = GenerationOptions(temperature: 0.2)
        do {
            let response = try await engine().respond(to: prompt, generating: TagSuggestions.self, options: options)
            return response.content.tags
        } catch {
            throw AiError(failure: .generationFailed)
        }
    }

    func close() {
        session = nil
    }
}
