import Foundation
import Observation
import OSLog

/// 家长今日概况只读当日事实，不把昨日跨日恢复实例算入今天分母。
///
/// 组合根拥有主actor可观察状态；构造不读取，PIN后页面才load，关闭门禁时reset。
@MainActor
@Observable
final class ParentTodayOverviewViewModel {
    private(set) var state: ParentTodayOverviewState = .idle
    private let service: GrowthStatisticsQueryService
    private let now: @MainActor () -> Date
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ParentTodayOverview")

    /// - Parameters:
    ///   - service: 组合根注入的当日只读查询。
    ///   - now: 只在主actor读取的可替换时钟，不由View直接读取系统时间。
    init(service: GrowthStatisticsQueryService, now: @escaping @MainActor () -> Date) {
        self.service = service
        self.now = now
    }

    /// 获取最新保存事实；空日的nil比率由页面表达“暂无数据”，不冒充0%。
    func load() {
        state = .loading
        do {
            state = .loaded(try service.today(at: now()))
        } catch {
            state = .failed
            logger.error("家长今日概况加载失败：\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// 门禁退出只清除内存展示，不写实例、账本或已读元数据。
    func reset() { state = .idle }
}
