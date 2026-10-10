import Observation
import OSLog
import SwiftData

/// 驱动家长模板列表，并隔离 SwiftData 查询与当前时间读取。
@MainActor
@Observable
final class ParentTaskTemplateListViewModel {
    private(set) var state: ParentTaskTemplateListState = .loading
    private(set) var showsSetupGuide = false
    private(set) var setupHasTask = false
    private var hasLoaded = false

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
            let items = try queryService.items(at: dateProvider.now())
            let hasConfiguration = try queryService.hasTaskConfiguration()
            // 引导仅在本家长会话从空配置开始时出现；保存后跳到提醒，旧家庭不重新引导。
            if !hasLoaded { showsSetupGuide = !hasConfiguration }
            setupHasTask = hasConfiguration
            hasLoaded = true
            state = .loaded(items)
        } catch {
            logger.error("家长模板列表加载失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
    }

    /// 用户已打开正式提醒页；检查提醒不是开始任务的硬性前置条件。
    func finishSetupGuide() { showsSetupGuide = false }
}
