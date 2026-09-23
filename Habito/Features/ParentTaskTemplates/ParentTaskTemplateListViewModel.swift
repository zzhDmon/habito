import Observation
import OSLog
import SwiftData

/// 驱动家长模板列表，并隔离 SwiftData 查询与当前时间读取。
@MainActor
@Observable
final class ParentTaskTemplateListViewModel {
    private(set) var state: ParentTaskTemplateListState = .loading

    private let queryService: ParentTaskTemplateQueryService
    private let dateProvider: any DateProviding
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ParentTemplates")

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding
    ) {
        queryService = ParentTaskTemplateQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        )
        self.dateProvider = dateProvider
    }

    /// 重新读取模板；页面每次进入前台或从后续编辑页返回时可以安全重复调用。
    func load() {
        state = .loading
        do {
            state = .loaded(try queryService.items(at: dateProvider.now()))
        } catch {
            logger.error("家长模板列表加载失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
    }
}
