import EventKit
import EventKitUI
import SwiftUI

/// 詳細シートの「AIで日付を探してカレンダーに追加」。
///
/// 見つかった予定が1件なら、考え終わった時点でそのまま標準カレンダーの
/// 新規予定画面を開く。複数あれば候補として並べて選んでもらう。どちらの場合も
/// 開くのは保存前の画面なので、最終的な確認と保存はカレンダー側で行われる。
/// iOS 17以降の `EKEventEditViewController` はOSが別プロセスで出すので、
/// カレンダーへのアクセス許可も要らない。
///
/// 予定が見つかったら、開く前にリンクの内容の要約も作ってメモ欄に入れる。
/// 見つからなかったときに要約まで待たせないよう、日付探しとは別に後から聞く。
@available(iOS 26.0, *)
struct CalendarSection: View {
    let item: StashItem

    @State private var candidates: [CalendarCandidate] = []
    @State private var searching = false
    @State private var summarizing = false
    @State private var failed = false
    /// 予定のメモ欄に入れる文。候補を選び直したときも作り直さずに使い回す
    @State private var notes: String?
    /// 新規予定画面に渡している予定。nil でなければ画面が出ている
    @State private var editing: CalendarCandidate?

    var body: some View {
        // 日付らしい書き方が無ければ、押しても空振りするだけ
        if CalendarExtract.mayContainDate(item) {
            content
                .sheet(item: $editing) { candidate in
                    EventEditView(
                        candidate: candidate,
                        notes: notes ?? CalendarExtract.calendarNotes(summary: nil, item: item),
                        url: URL(string: item.url)
                    )
                    .ignoresSafeArea()
                }
                // 詳細シートは同じ枠のまま別のリンクに切り替わることがある
                .onChange(of: item.id) {
                    candidates = []
                    failed = false
                    notes = nil
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !candidates.isEmpty {
            VStack(spacing: 8) {
                ForEach(candidates) { candidate in
                    // 自動で開いた後にカレンダー側で閉じてしまっても、ここから開き直せる
                    CandidateRow(candidate: candidate) { open(candidate) }
                }
            }
        } else if searching {
            Text(L.s(summarizing ? "ai_calendar_summarizing" : "ai_thinking"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .padding(.vertical, 6)
        } else {
            TextLink(
                text: L.s(failed ? "ai_calendar_retry" : "ai_calendar_action"),
                icon: Lucide.calendarPlus,
                action: search
            )
        }
    }

    private func search() {
        searching = true
        failed = false
        let session = AiSession()
        let prompt = CalendarExtract.buildPrompt(
            instruction: L.s("ai_calendar_instruction"), item: item, now: Date()
        )
        Task {
            // タグ提案と同じく、失敗したら「もう一度試す」だけ見せる
            let raw = (try? await session.findCalendarEvents(prompt: prompt)) ?? ""
            let found = CalendarExtract.parse(raw, item: item)
            if !found.isEmpty, notes == nil {
                summarizing = true
                let summary = (try? await session.respond(
                    prompt: CalendarExtract.buildSummaryPrompt(
                        instruction: L.s("ai_calendar_summary_instruction"), item: item
                    )
                )).flatMap(CalendarExtract.parseSummary)
                notes = CalendarExtract.calendarNotes(summary: summary, item: item)
                summarizing = false
            }
            candidates = found
            failed = found.isEmpty
            searching = false
            // 1件ならどれを入れるか迷う余地が無いので、そのままカレンダーへ送る。
            // 複数あるときは勝手に1つを選ばず、並べて選んでもらう
            if found.count == 1 { open(found[0]) }
        }
    }

    private func open(_ candidate: CalendarCandidate) {
        editing = candidate
        AppAnalytics.bookmarkAction("calendar_add")
    }
}

/// 見つけた予定1件。日付と予定名を並べ、タップでカレンダーの新規予定を開く
private struct CandidateRow: View {
    let candidate: CalendarCandidate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIconView(icon: Lucide.calendarPlus, size: 18, color: Palette.accent700)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.label)
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(whenText)
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.accent800)
                }
                Spacer(minLength: 0)
                Text(L.s("ai_calendar_add"))
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.accent700)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.accent100))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.accent.opacity(0.4), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressScale(0.97))
    }

    /// 「2026年8月24日(月) · 終日」「2026年8月24日(月) 10:00」
    private var whenText: String {
        let date = candidate.beginDate()
        let formatter = DateFormatter()
        // 年は常に4桁で出す。端末の設定によっては2桁になり「26年」と読みにくい
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMdEEE")
        let datePart = formatter.string(from: date)
        guard !candidate.allDay else { return "\(datePart) · \(L.s("ai_calendar_all_day"))" }
        return "\(datePart) \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// 標準カレンダーの新規予定画面。日時・予定名・メモを埋めた状態で出す
private struct EventEditView: UIViewControllerRepresentable {
    let candidate: CalendarCandidate
    let notes: String
    let url: URL?

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = candidate.label
        event.isAllDay = candidate.allDay
        event.startDate = candidate.beginDate()
        // 終日の予定は、終わりをその日の中に置くと1日ぶんになる。
        // 翌日0時にすると2日にまたがって見えるカレンダーがある
        event.endDate = candidate.allDay ? candidate.beginDate() : candidate.endDate()
        event.notes = notes
        event.url = url
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            dismiss()
        }
    }
}
