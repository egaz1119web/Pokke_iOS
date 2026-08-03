import SwiftUI

/// 詳細シートのリマインダー欄。
///
/// 候補は「明日の朝」ひとつだけ。時刻を細かく決めたいときは日時を指定する。
/// どちらも「今から必ず未来になる」ので、押した瞬間に過去の時刻が入ることはない。
struct ReminderSection: View {
    let item: StashItem

    @EnvironmentObject private var toast: ToastController
    @ObservedObject private var scheduler = ReminderScheduler.shared

    /// 設定済みでも候補を出している最中か（「変更」を押した後）
    @State private var editing = false
    @State private var showDatePicker = false
    /// 設定しようとして許可が下りなかった。断られたことは覚えられていないので自分で持つ
    @State private var permissionDenied = false

    private var pending: Bool { ReminderPlan.isPending(item.remindAt, now: nowMillis()) }

    /// 通知を切られている案内を出すか。
    /// 一度断られるとOSは聞き直してくれないので、設定アプリへ送るしかない
    private var showsPermissionNotice: Bool {
        permissionDenied || scheduler.authorization == .denied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.s("detail_reminder"))
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.neutral700)

            if let remindAt = item.remindAt, !editing {
                currentReminder(remindAt: remindAt)
            } else {
                choices
            }

            if showsPermissionNotice {
                permissionNotice
            }
        }
        .sheet(isPresented: $showDatePicker) {
            ReminderDateSheet(initial: initialPickerDate) { picked in
                apply(date: picked)
            }
        }
        .task { await scheduler.refreshAuthorization() }
    }

    /// 設定済みの表示。鳴る前は予定、鳴った後は履歴として見せる
    private func currentReminder(remindAt: EpochMillis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(
                    icon: Lucide.bell,
                    tint: pending ? Palette.accent100 : Palette.neutral200,
                    foreground: pending ? Palette.accent700 : Palette.neutral600,
                    size: 36,
                    iconSize: 16,
                    cornerRadius: 12
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminderTimeText(remindAt))
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(Palette.ink)
                    Text(L.s(pending ? "reminder_pending" : "reminder_elapsed"))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.neutral600)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                OutlinedPillButton(title: L.s("reminder_change"), height: 38) {
                    editing = true
                }
                OutlinedPillButton(title: L.s("reminder_clear"), height: 38) {
                    StashRepository.shared.setReminder(id: item.id, at: nil)
                    editing = false
                    toast.show(L.s("reminder_cleared"))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Corner.medium, style: .continuous).fill(Palette.surface)
        )
    }

    /// 候補と日時指定
    private var choices: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(ReminderPlan.Preset.allCases) { preset in
                    ReminderChip(text: L.s(preset.labelKey), icon: Lucide.clock) {
                        apply(date: ReminderPlan.date(for: preset, now: Date()))
                    }
                }
                ReminderChip(text: L.s("reminder_pick_date"), icon: Lucide.bell) {
                    showDatePicker = true
                }
            }

            // 設定済みから「変更」で開いたときだけ、やめて戻れるようにする
            if item.remindAt != nil, editing {
                Button {
                    editing = false
                } label: {
                    Text(L.s("action_cancel"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.neutral600)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permissionNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIconView(icon: Lucide.triangleAlert, size: 16, color: Palette.accent800)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.s("reminder_permission_denied"))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.accent800)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// 日時指定を開いたときの初期値。設定済みならその時刻、無ければ明日の朝
    private var initialPickerDate: Date {
        if let remindAt = item.remindAt, remindAt > nowMillis() { return Date(epochMillis: remindAt) }
        return ReminderPlan.date(for: .tomorrowMorning, now: Date())
    }

    /// 通知の許可を確かめてから保存する。
    /// 許可が無いまま時刻だけ持たせても鳴らないので、その場合は入れない
    private func apply(date: Date) {
        Task {
            guard await ReminderScheduler.shared.requestAuthorization() else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            // 押すまでの間に時刻が過ぎていることがある（候補を出したまま放置した等）
            let at = ReminderPlan.notBefore(date, now: Date())
            StashRepository.shared.setReminder(id: item.id, at: at.epochMillis)
            editing = false
            toast.show(L.s("reminder_set", reminderTimeText(at.epochMillis)))
        }
    }
}

/// 候補ひとつぶんのチップ
private struct ReminderChip: View {
    let text: String
    let icon: Lucide.Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIconView(icon: icon, size: 13, color: Palette.neutral700)
                Text(text)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.neutral800)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.95))
    }
}

/// 日時を自分で決めるシート
private struct ReminderDateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onPick: (Date) -> Void

    @State private var date: Date

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        _date = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHandle()
            Text(L.s("reminder_pick_date"))
                .font(PokkeType.titleSmall)
                .foregroundStyle(Palette.ink)

            DatePicker(
                L.s("reminder_pick_date"),
                selection: $date,
                // 過ぎた日時は選ばせない。選べても鳴らないだけなので
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .tint(Palette.accent)
            .labelsHidden()
            .padding(.top, 8)

            PrimaryButton(title: L.s("reminder_pick_confirm")) {
                onPick(date)
                dismiss()
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        .presentationDetents([.fraction(0.82)])
    }
}
