import Foundation
import Observation
import OSLog

/// 统计页面只消费查询快照，窗口切换和刷新都重读已保存事实。
///
/// `@Observable`由组合根拥有、View观察；所有状态和同步SwiftData读取归主actor。
/// 构造不查询历史，必须在通过PIN后的页面显式load；时钟闭包同样在主actor调用。
@MainActor
@Observable
final class GrowthStatisticsViewModel {
    private(set) var state: GrowthStatisticsViewState = .idle
    private(set) var period: GrowthStatisticsPeriod = .week
    private let service: GrowthStatisticsQueryService
    private let now: @MainActor () -> Date
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "GrowthStatistics")

    /// - Parameters:
    ///   - service: 组合根注入的真实只读查询边界。
    ///   - now: 主actor墙上时钟边界；测试可推进固定时刻而无需等待。
    init(service: GrowthStatisticsQueryService, now: @escaping @MainActor () -> Date) {
        self.service = service
        self.now = now
    }

    /// 已解锁页面选择7/14/30天；同窗口也允许重读，避免保存后的事实被缓存掩盖。
    func select(_ period: GrowthStatisticsPeriod) {
        self.period = period
        load()
    }

    /// 同时撤下旧内容与错误；失败显示可重试状态，不把旧比例留给家长误读。
    func load() {
        state = .loading
        do {
            state = .loaded(try service.snapshot(period: period, at: now()))
        } catch {
            state = .failed
            // 诊断只记录错误类型，避免任务名、日期和家庭资料进入日志。
            logger.error("成长统计加载失败：\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// 关闭家长入口时撤下历史；再次解锁由页面重新加载，不沿用旧窗口和旧快照。
    func reset() {
        state = .idle
        period = .week
    }
}
