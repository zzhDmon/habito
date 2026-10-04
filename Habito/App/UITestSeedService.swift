#if DEBUG
    import Foundation
    import SwiftData

    /// 为 UI 自动化准备可重复、可跨进程恢复的最小孩子闭环数据。
    ///
    /// 该服务只编译进 Debug 包，并由专用启动参数调用。固定 UUID 让 UI 测试可以定位具体任务；
    /// 日期和绝对时间仍基于启动时刻生成，确保任务在设备当前日历与时区中属于“今天”。
    @MainActor
    enum UITestSeedService {
        static let taskID = UUID(
            uuid: (0xc5, 0x41, 0x21, 0x44, 0x2f, 0xb8, 0x4e, 0x96, 0x9f, 0x7a, 0x6a, 0x42, 0xe0, 0x80, 0x3d, 0x11)
        )
        private static let templateID = UUID(
            uuid: (0x67, 0x43, 0xa0, 0x0b, 0x87, 0x8f, 0x4b, 0xb0, 0xa8, 0x61, 0x64, 0x05, 0x6e, 0xc1, 0x9f, 0xe5)
        )

        /// 必要时清理测试容器并写入唯一的待处理任务。
        ///
        /// - Parameters:
        ///   - container: UI 测试独占的磁盘容器。
        ///   - shouldReset: 是否清空上一次测试状态。重启恢复场景必须传 `false`。
        ///   - shouldSeedSampleData: 是否写入固定样例；空数据验收只清理、不播种。
        ///   - now: 用于生成“今天”测试数据的绝对时间。
        ///   - calendar: 解释本地日期的日历。
        ///   - timeZone: 解释本地日期的时区。
        /// - Throws: 查询、清理、日期转换或保存失败时抛出错误，阻止测试使用半初始化数据。
        static func prepare(
            container: ModelContainer,
            shouldReset: Bool,
            shouldSeedSampleData: Bool = true,
            now: Date,
            calendar: Calendar,
            timeZone: TimeZone
        ) throws {
            let context = container.mainContext
            if shouldReset {
                try removeAllData(from: context)
            }
            guard shouldSeedSampleData else { return }

            let existing = try context.fetch(
                FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == taskID })
            )
            guard existing.isEmpty else { return }

            let localDate = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
            let template = TaskTemplate(
                id: templateID,
                title: "阅读 15 分钟",
                iconName: "book.fill",
                colorToken: "task",
                targetDurationSeconds: 900,
                createdAt: now,
                updatedAt: now
            )
            let occurrence = TaskOccurrence(
                id: taskID,
                templateID: templateID,
                date: localDate,
                scheduledAt: now.addingTimeInterval(-60),
                titleSnapshot: template.title,
                iconSnapshot: template.iconName,
                colorSnapshot: template.colorToken,
                targetDurationSnapshot: template.targetDurationSeconds,
                sourceRevision: template.revision,
                createdAt: now,
                updatedAt: now
            )
            let rule = ReminderRule(
                taskTemplateID: templateID,
                recurrence: try .weekly(on: Set(Weekday.allCases), starting: localDate),
                timeOfDayMinutes: 19 * 60 + 30
            )
            context.insert(template)
            context.insert(rule)
            context.insert(occurrence)
            // 与正式创建服务一致：先入同一 context，再关联，兼容 iPadOS 17 的关系维护。
            template.reminderRule = rule
            rule.taskTemplate = template
            occurrence.template = template
            try context.save()
        }

        private static func removeAllData(from context: ModelContext) throws {
            // 先删除关系叶子，再删除实例和模板，避免让级联删除顺序影响测试重置的确定性。
            try context.fetch(FetchDescriptor<NotificationLink>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CompletionRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TimerSession>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TaskOccurrence>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ReminderRule>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TaskTemplate>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<DayOverride>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<AppSettings>()).forEach(context.delete)
            try context.save()
        }
    }
#endif
