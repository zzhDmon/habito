import Foundation
import Observation
import OSLog

/// 持有编辑草稿、时间控件状态，并协调加载与保存事务。
@MainActor
@Observable
final class TaskTemplateEditorViewModel {
    var draft: TaskTemplateDraft
    var scheduledTime: Date
    private(set) var feedback: TaskTemplateEditorFeedback?
    private(set) var lifecycleImpact: TaskTemplateLifecycleImpact?
    private(set) var isLoading = true
    private(set) var isSaving = false

    let isCreating: Bool
    private let templateID: UUID?
    private let service: TaskTemplateEditingService
    private let lifecycleService: TaskTemplateLifecycleService
    private let dateProvider: any DateProviding
    private var calendar: Calendar
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "TemplateEditor")
    private var didLoad = false

    var hasLoadFailure: Bool {
        feedback == .loadFailure
    }

    init(
        templateID: UUID?,
        service: TaskTemplateEditingService,
        lifecycleService: TaskTemplateLifecycleService,
        dateProvider: any DateProviding,
        calendar: Calendar,
        timeZone: TimeZone
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.templateID = templateID
        self.service = service
        self.lifecycleService = lifecycleService
        self.dateProvider = dateProvider
        self.calendar = configuredCalendar
        draft = .new
        scheduledTime = Self.makeTimeDate(
            minutes: TaskTemplateDraft.new.timeOfDayMinutes,
            calendar: configuredCalendar
        )
        isCreating = templateID == nil
    }

    /// 首次展示时加载编辑对象；重复触发 `.task` 不会覆盖用户尚未保存的输入。
    func load() {
        guard !didLoad else { return }
        didLoad = true
        feedback = nil
        do {
            if let templateID {
                draft = try service.load(templateID: templateID)
                scheduledTime = Self.makeTimeDate(
                    minutes: draft.timeOfDayMinutes,
                    calendar: calendar
                )
            }
            isLoading = false
        } catch {
            logger.error("任务编辑器加载失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = .loadFailure
            isLoading = false
        }
    }

    /// 保存当前草稿；成功返回 `true`，失败保留页面和可理解反馈。
    func save() -> Bool {
        feedback = nil
        isSaving = true
        defer { isSaving = false }
        var value = draft
        let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
        value.timeOfDayMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        do {
            _ = try service.save(value, at: dateProvider.now())
            draft = value
            return true
        } catch let error as TaskTemplateEditorError {
            feedback = .validation(error)
            return false
        } catch {
            logger.error("任务编辑器保存失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = .storageFailure
            return false
        }
    }

    func toggle(_ weekday: Weekday) {
        if draft.weekdays.contains(weekday) {
            draft.weekdays.remove(weekday)
        } else {
            draft.weekdays.insert(weekday)
        }
    }

    /// 在展示确认框前重新读取持久化实例，保证影响数量不是页面启动时的旧快照。
    func prepareLifecycleAction(_ action: TaskTemplateLifecycleAction) {
        guard let templateID else { return }
        feedback = nil
        do {
            lifecycleImpact = try lifecycleService.preview(
                templateID: templateID,
                action: action,
                today: try currentLocalDate()
            )
        } catch {
            logger.error("任务生命周期预览失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = .storageFailure
        }
    }

    /// 使用确认时的最新数据执行操作；归档成功后由页面关闭，其他动作原地刷新草稿。
    func confirmLifecycleAction() -> TaskTemplateLifecycleAction? {
        guard let impact = lifecycleImpact else { return nil }
        do {
            _ = try lifecycleService.perform(
                templateID: impact.templateID,
                action: impact.action,
                today: try currentLocalDate(),
                now: dateProvider.now()
            )
            lifecycleImpact = nil
            if impact.action != .archive {
                draft = try service.load(templateID: impact.templateID)
            }
            return impact.action
        } catch {
            logger.error("任务生命周期操作失败：\(String(describing: type(of: error)), privacy: .public)")
            lifecycleImpact = nil
            feedback = .storageFailure
            return nil
        }
    }

    func cancelLifecycleAction() {
        lifecycleImpact = nil
    }

    private func currentLocalDate() throws -> LocalDate {
        try LocalDate(date: dateProvider.now(), calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func makeTimeDate(minutes: Int, calendar: Calendar) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2001,
                month: 1,
                day: 1,
                hour: minutes / 60,
                minute: minutes % 60
            )
        ) ?? .now
    }
}
