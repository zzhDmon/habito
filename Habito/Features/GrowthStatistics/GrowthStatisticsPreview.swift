import Foundation

/// 预览仅使用固定纯值，不创建容器、写家庭数据库或读取真实时钟。
enum GrowthStatisticsPreview {
    static var state: GrowthStatisticsViewState { makeState(completed: false, empty: false) }
    static var completedState: GrowthStatisticsViewState { makeState(completed: true, empty: false) }
    static var emptyState: GrowthStatisticsViewState { makeState(completed: false, empty: true) }

    private static func makeState(completed: Bool, empty: Bool) -> GrowthStatisticsViewState {
        do {
            let date = try LocalDate(dateKey: "2026-09-23")
            let fact = GrowthStatisticsFact(
                id: UUID(), templateID: UUID(), date: date,
                title: "固定合成阅读", status: completed ? .completed : .pending,
                isAwaitingReview: false, completionTiming: completed ? .beforeReminder : nil,
                completionSource: completed ? .childManual : nil)
            return .loaded(
                try GrowthStatisticsCalculator().snapshot(facts: empty ? [] : [fact], endingOn: date, period: .week))
        } catch { return .failed }
    }
}
