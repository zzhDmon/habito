import Foundation

/// 孩子页面导航所需的最小只读任务值。
///
/// 它刻意不持有 SwiftData 模型，避免页面导航期间绑定可变持久化对象。
/// 该值由查询结果生成，并在每次进入任务页时按稳定 ID 重新加载。
struct KidTaskNavigationItem: Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let iconName: String
    let scheduledTimeText: String
    let plannedTimeText: String?
    let deadlineTimeText: String?
    let timing: TaskTimingSnapshot
    let targetDurationText: String
    let status: TaskOccurrenceStatus
    let statusText: String
    let statusIconName: String
    let timePeriod: TaskTimePeriod
    let isCarryOver: Bool

    /// 把领域查询值转换为孩子界面和导航共用的稳定展示值。
    ///
    /// 日历由组合根注入，避免时间文案偷偷依赖设备当前设置。
    init(item: TodayTaskItem, calendar: Calendar, referenceDate: LocalDate? = nil) {
        // 三种时刻统一用注入时区和原有 24 小时中文样式，不在 View 读取设备设置。
        let timeStyle = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: Locale(identifier: "zh_Hans_CN"),
            calendar: calendar, timeZone: calendar.timeZone
        ).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        let targetMinutes = max(1, Int(ceil(item.targetDurationSeconds / 60)))

        id = item.id
        title = item.title
        iconName = item.iconName
        scheduledTimeText = item.scheduledAt.formatted(timeStyle)
        plannedTimeText = item.timing.plannedAt.map { $0.formatted(timeStyle) }
        deadlineTimeText = item.timing.deadlineAt.map { $0.formatted(timeStyle) }
        timing = item.timing
        targetDurationText = String.localizedStringWithFormat(
            String(localized: "kidTask.durationMinutesFormat"),
            targetMinutes
        )
        status = item.status
        timePeriod = item.timePeriod
        isCarryOver = item.status == .inProgress && referenceDate.map { item.date < $0 } == true

        if item.isAwaitingReview {
            statusText = String(localized: "kidTask.statusAwaitingReview")
            statusIconName = "hourglass.circle.fill"
        } else if item.submission?.state == .returned, item.status == .pending {
            statusText = String(localized: "kidTask.statusReturned")
            statusIconName = "arrow.uturn.backward.circle.fill"
        } else if isCarryOver {
            statusText = String(localized: "kidTask.statusCarryOver")
            statusIconName = "clock.arrow.circlepath"
        } else {
            switch item.status {
            case .pending:
                statusText = String(localized: "kidTask.statusPending")
                statusIconName = HabitoDesign.Symbol.pending
            case .inProgress:
                statusText = String(localized: "kidTask.statusInProgress")
                statusIconName = "play.circle.fill"
            case .completed:
                statusText = String(localized: "kidTask.statusCompleted")
                statusIconName = HabitoDesign.Symbol.completed
            case .skipped:
                statusText = String(localized: "kidTask.statusSkipped")
                statusIconName = "forward.end.circle.fill"
            }
        }
    }

    init(
        id: UUID,
        title: String,
        iconName: String,
        scheduledTimeText: String,
        targetDurationText: String,
        status: TaskOccurrenceStatus,
        statusText: String,
        statusIconName: String,
        timePeriod: TaskTimePeriod = .allDay,
        isCarryOver: Bool = false,
        plannedTimeText: String? = nil,
        deadlineTimeText: String? = nil,
        timing: TaskTimingSnapshot = .unspecified
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.scheduledTimeText = scheduledTimeText
        self.plannedTimeText = plannedTimeText
        self.deadlineTimeText = deadlineTimeText
        self.timing = timing
        self.targetDurationText = targetDurationText
        self.status = status
        self.statusText = statusText
        self.statusIconName = statusIconName
        // 手动构造仅用于 Preview/测试；生产值经查询校验后从上面的 init(item:) 传播。
        self.timePeriod = timePeriod
        self.isCarryOver = isCarryOver
    }
}

extension KidTaskNavigationItem {
    /// 只供 Preview 使用，不会写入正式数据容器。
    static let previewReading = KidTaskNavigationItem(
        id: UUID(),
        title: String(localized: "kidTask.previewTitle"),
        iconName: "book.fill",
        scheduledTimeText: String(localized: "kidTask.previewTime"),
        targetDurationText: String(localized: "kidTask.previewDuration"),
        status: .pending,
        statusText: String(localized: "kidTask.statusPending"),
        statusIconName: HabitoDesign.Symbol.pending
    )

    static let previewWriting = KidTaskNavigationItem(
        id: UUID(),
        title: String(localized: "kidTask.previewWritingTitle"),
        iconName: "pencil.line",
        scheduledTimeText: String(localized: "kidTask.previewWritingTime"),
        targetDurationText: String(localized: "kidTask.previewWritingDuration"),
        status: .pending,
        statusText: String(localized: "kidTask.statusPending"),
        statusIconName: HabitoDesign.Symbol.pending
    )

    static let previewCompleted = KidTaskNavigationItem(
        id: UUID(),
        title: String(localized: "kidTask.previewCompletedTitle"),
        iconName: "checkmark.seal.fill",
        scheduledTimeText: String(localized: "kidTask.previewCompletedTime"),
        targetDurationText: String(localized: "kidTask.previewCompletedDuration"),
        status: .completed,
        statusText: String(localized: "kidTask.statusCompleted"),
        statusIconName: HabitoDesign.Symbol.completed
    )
}
