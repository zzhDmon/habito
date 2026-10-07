#if DEBUG
    import Foundation
    import SwiftData

    /// 显式隔离UI测试才注入一次读取失败；不损坏合成数据库，也不接触正式库。
    @MainActor
    enum UITestStatisticsServiceFactory {
        static let failureArgument = "--habito-ui-statistics-read-fail-once"

        static func make(
            context: ModelContext, calendar: Calendar, timeZone: TimeZone,
            arguments: [String]
        ) -> GrowthStatisticsQueryService {
            guard arguments.contains(UITestLaunchConfiguration.enableArgument), arguments.contains(failureArgument)
            else { return GrowthStatisticsQueryService(context: context, calendar: calendar, timeZone: timeZone) }
            var shouldFail = true
            return GrowthStatisticsQueryService(
                context: context, calendar: calendar, timeZone: timeZone,
                fetchOccurrences: { descriptor in
                    if shouldFail {
                        shouldFail = false
                        throw NSError(domain: "HabitoSyntheticUIStatisticsRead", code: 1)
                    }
                    return try context.fetch(descriptor)
                })
        }
    }
#endif
