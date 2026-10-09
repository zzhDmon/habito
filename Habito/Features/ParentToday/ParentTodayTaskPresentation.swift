import SwiftUI

/// 原始pending可能正在等待；来源与自主性使用不同文本，不在View重复业务判断。
struct ParentTodayTaskPresentation {
    let item: TodayTaskItem

    var statusKey: LocalizedStringKey {
        if item.isAwaitingReview { return "parentToday.statusWaiting" }
        return switch item.status {
        case .pending: "parentToday.statusPending"
        case .inProgress: "parentToday.statusInProgress"
        case .completed: "parentToday.statusCompleted"
        case .skipped: "parentToday.statusSkipped"
        case .cancelled: "parentToday.statusDeleted"
        }
    }

    var statusSymbol: String {
        if item.isAwaitingReview { return "hourglass" }
        return switch item.status {
        case .pending: "clock"
        case .inProgress: "timer"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.end.fill"
        case .cancelled: "xmark.circle"
        }
    }

    var completionSourceKey: LocalizedStringKey? {
        switch item.completion?.source {
        case .childManual: "statistics.sourceChild"
        case .parentApproval: "statistics.sourceApproval"
        case .parentCorrection: "parentToday.parentCorrection"
        case nil: nil
        }
    }

    var completionTimingKey: LocalizedStringKey? {
        switch item.completion?.timing {
        case .beforeReminder: "statistics.autonomous"
        case .afterReminder: "statistics.afterReminder"
        case .unknown: "statistics.unknownTiming"
        case nil: nil
        }
    }

    /// 等待没有通用编辑/跳过/完成菜单；应去审核页处理已有提交。
    var canManage: Bool { !item.isAwaitingReview && (item.status == .pending || item.status == .skipped) }
}
