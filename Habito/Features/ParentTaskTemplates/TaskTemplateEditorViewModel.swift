import Foundation
import Observation
import OSLog

/// 持有编辑草稿、时间控件状态，并协调加载与保存事务。
@MainActor
@Observable
final class TaskTemplateEditorViewModel {
    var draft: TaskTemplateDraft
    var rewardInput: TaskTemplateRewardInput
    var scheduledTime: Date

    /// 可空分钟是唯一草稿真相；关闭立即清空，避免另存布尔状态与旧值漂移。
    ///
    /// 首次明确启用时采用当前可见提醒时刻作为输入候选，家长可立即调整；
    /// 不在加载旧 nil 或保存未启用控件时自动补值。
    var isPlannedTimeEnabled: Bool {
        get { draft.plannedTimeOfDayMinutes != nil }
        set {
            if !newValue {
                draft.plannedTimeOfDayMinutes = nil
            } else if draft.plannedTimeOfDayMinutes == nil {
                draft.plannedTimeOfDayMinutes = timeMinutes(from: scheduledTime)
            }
        }
    }

    /// 截止与计划独立，没有强制先后关系；开启和清空只修改纯值草稿，不写库。
    var isDeadlineTimeEnabled: Bool {
        get { draft.deadlineTimeOfDayMinutes != nil }
        set {
            if !newValue {
                draft.deadlineTimeOfDayMinutes = nil
            } else if draft.deadlineTimeOfDayMinutes == nil {
                draft.deadlineTimeOfDayMinutes = timeMinutes(from: scheduledTime)
            }
        }
    }

    /// DatePicker 的日期部分仅是固定锚点；保存的是注入时区下的时分。
    var plannedTime: Date {
        get { Self.makeTimeDate(minutes: draft.plannedTimeOfDayMinutes, calendar: calendar) ?? scheduledTime }
        set { draft.plannedTimeOfDayMinutes = timeMinutes(from: newValue) }
    }

    /// 与计划使用同一转换边界，但直接绑定独立可空截止分钟。
    var deadlineTime: Date {
        get { Self.makeTimeDate(minutes: draft.deadlineTimeOfDayMinutes, calendar: calendar) ?? scheduledTime }
        set { draft.deadlineTimeOfDayMinutes = timeMinutes(from: newValue) }
    }

    /// 原生控件必须和分钟转换使用同一日历/时区，不能依赖设备设置恰好一致。
    var timeInputCalendar: Calendar { calendar }
    private(set) var feedback: TaskTemplateEditorFeedback?
    private(set) var lifecycleImpact: TaskTemplateLifecycleImpact?
    private(set) var isLoading = true
    private(set) var isSaving = false

    let isCreating: Bool
    private let templateID: UUID?
    private let service: TaskTemplateEditingService
    private let lifecycleService: TaskTemplateLifecycleService
    private let notificationPermissionService: NotificationPermissionService
    private let notificationRebuildTrigger: NotificationRebuildTrigger
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
        notificationPermissionService: NotificationPermissionService,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger(),
        dateProvider: any DateProviding,
        calendar: Calendar,
        timeZone: TimeZone
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.templateID = templateID
        self.service = service
        self.lifecycleService = lifecycleService
        self.notificationPermissionService = notificationPermissionService
        self.notificationRebuildTrigger = notificationRebuildTrigger
        self.dateProvider = dateProvider
        self.calendar = configuredCalendar
        draft = .new
        rewardInput = TaskTemplateRewardInput(draft: .new)
        // 加载期间的有限占位值不能保存；真正控件值在 load 中校验固定日历锚点后生成。
        scheduledTime = Date(timeIntervalSinceReferenceDate: 0)
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
                rewardInput = TaskTemplateRewardInput(draft: draft)
            }
            guard let time = Self.makeTimeDate(minutes: draft.timeOfDayMinutes, calendar: calendar) else {
                throw TaskTemplateEditorError.invalidTime
            }
            scheduledTime = time
            isLoading = false
        } catch {
            logger.error("任务编辑器加载失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = .loadFailure
            isLoading = false
        }
    }

    /// 保存当前草稿；首次创建成功后才请求通知权限，权限问题不会回滚任务。
    func save() async -> TaskTemplateSaveOutcome {
        // 载入失败不是空白新任务；保留错误状态，不能让保存操作创建另一个模板。
        // 同时保护尚未载入或正在保存的入口，UI 禁用之外仍要防止重复意图。
        guard !isLoading, !isSaving, !hasLoadFailure else { return .failed }
        feedback = nil
        isSaving = true
        defer { isSaving = false }
        var value = draft
        value.timeOfDayMinutes = timeMinutes(from: scheduledTime)
        do {
            // 先校验原文再写入，不能把无效输入当作“没有修改”而保存旧奖励。
            value = try rewardInput.applying(to: value)
            _ = try service.save(value, at: dateProvider.now())
            draft = value
            rewardInput = TaskTemplateRewardInput(draft: value)
            notificationRebuildTrigger.requestRebuild()
            guard isCreating else { return .saved }
            // 首轮重建可能在权限弹窗等待期间已结束；授权返回后必须显式按最新系统状态再核对。
            // 失败也可能发生在系统已改变权限之后，因此不能只依赖弹窗是否触发 scenePhase 切换。
            defer { notificationRebuildTrigger.requestRebuild() }
            do {
                _ = try await notificationPermissionService.requestIfNeeded()
                return .saved
            } catch {
                logger.error("通知权限状态读取失败：\(String(describing: type(of: error)), privacy: .public)")
                return .savedWithNotificationWarning
            }
        } catch let error as TaskTemplateEditorError {
            feedback = .validation(error)
            return .failed
        } catch {
            logger.error("任务编辑器保存失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = .storageFailure
            return .failed
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
            notificationRebuildTrigger.requestRebuild()
            lifecycleImpact = nil
            if impact.action != .archive {
                draft = try service.load(templateID: impact.templateID)
                rewardInput = TaskTemplateRewardInput(draft: draft)
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

    /// 非有限控件值用非法分钟传入既有校验路径，明确失败而不是静默保存为午夜。
    ///
    /// - Returns: 有效时分为 0...1439；-1 仅表示坏输入，服务写前拒绝，绝不作为配置落库。
    private func timeMinutes(from date: Date) -> Int {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return -1 }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute,
            (0..<24).contains(hour), (0..<60).contains(minute)
        else { return -1 }
        return hour * 60 + minute
    }

    private static func makeTimeDate(minutes: Int?, calendar: Calendar) -> Date? {
        guard let minutes, (0..<1440).contains(minutes) else { return nil }
        return calendar.date(
            from: DateComponents(
                year: 2001,
                month: 1,
                day: 1,
                hour: minutes / 60,
                minute: minutes % 60
            )
        )
    }
}
