#if DEBUG
    import Foundation
    import SwiftData

    /// 仅显式UI隔离环境替换附加资格读取；正式事务、今日任务和资产查询保持真实。
    @MainActor
    enum UITestTodayViewModelFactory {
        static let qualificationFailureArgument = "--habito-ui-daily-qualification-fail"

        /// 故障持续到移除启动标志，避免自动刷新提前清除待验的错误状态。
        /// - Important: 单独故障标志无效；Release不编译此工厂，也不修改存储内容。
        static func make(
            context: ModelContext, calendar: Calendar, timeZone: TimeZone,
            dateProvider: any DateProviding, arguments: [String]
        ) -> TodayViewModel {
            let enabled =
                arguments.contains(UITestLaunchConfiguration.enableArgument)
                && arguments.contains(qualificationFailureArgument)
            let read: (() throws -> TodayTasksSnapshot)? =
                enabled
                ? { throw NSError(domain: "HabitoSyntheticDailyQualificationRead", code: 1) } : nil
            return TodayViewModel(
                context: context, calendar: calendar, timeZone: timeZone, dateProvider: dateProvider,
                readCelebrationSnapshot: read)
        }
    }
#endif
