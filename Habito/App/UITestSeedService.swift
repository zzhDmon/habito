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
        ///   - shouldSeedTemplateOnly: 仅保留模板，不预建实例，用于验证启动重建与首页刷新。
        ///   - now: 用于生成“今天”测试数据的绝对时间。
        ///   - calendar: 解释本地日期的日历。
        ///   - timeZone: 解释本地日期的时区。
        ///   - scenario: 显式合成验收/奖励场景；旧用例默认零奖励自行确认，不改产品默认。
        /// - Throws: 查询、清理、日期转换或保存失败时抛出错误，阻止测试使用半初始化数据。
        static func prepare(
            container: ModelContainer,
            shouldReset: Bool,
            shouldSeedSampleData: Bool = true,
            shouldSeedTemplateOnly: Bool = false,
            now: Date,
            calendar: Calendar,
            timeZone: TimeZone,
            scenario: UITestTaskScenario = .legacy
        ) throws {
            let context = container.mainContext
            if shouldReset {
                try removeAllData(from: context)
            }
            guard shouldSeedSampleData else { return }

            // 重启时不要因样例实例已被停用/归档清理而再次播种，覆盖家长之前的维护结果。
            let existing = try context.fetch(
                FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == templateID })
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
                updatedAt: now,
                verificationType: scenario.verificationType,
                xpReward: scenario.hasSyntheticReward ? 11 : 0,
                coinReward: scenario.hasSyntheticReward ? 7 : 0,
                activeBonusCoin: scenario.hasSyntheticReward ? 3 : 0
            )
            let occurrence = TaskOccurrence(
                id: taskID,
                templateID: templateID,
                date: localDate,
                scheduledAt: now.addingTimeInterval(scenario.reminderOffset),
                titleSnapshot: template.title,
                iconSnapshot: template.iconName,
                colorSnapshot: template.colorToken,
                targetDurationSnapshot: template.targetDurationSeconds,
                sourceRevision: template.revision,
                isDetachedOverride: scenario != .legacy,
                createdAt: now,
                updatedAt: now,
                verificationTypeSnapshot: scenario.verificationType,
                xpRewardSnapshot: template.xpReward,
                coinRewardSnapshot: template.coinReward,
                activeBonusCoinSnapshot: template.activeBonusCoin
            )
            let rule = ReminderRule(
                taskTemplateID: templateID,
                recurrence: try .weekly(on: Set(Weekday.allCases), starting: localDate),
                timeOfDayMinutes: 19 * 60 + 30
            )
            context.insert(template)
            context.insert(rule)
            // 与正式创建服务一致：先入同一 context，再关联，兼容 iPadOS 17 的关系维护。
            template.reminderRule = rule
            rule.taskTemplate = template
            if !shouldSeedTemplateOnly {
                context.insert(occurrence)
                occurrence.template = template
            }
            try context.save()
            if scenario == .petCare {
                try FamilyProfileService(context: context).save(
                    FamilyProfileNames(childNickname: "合成孩子", petName: "合成毛球"))
                _ = try RewardLedgerService(context: context).grantReward(sourceID: UUID(), xp: 95, coins: 12, at: now)
            }
            if scenario == .dailyIncome {
                // 独占测试库通过真实账本播种跨日收入和消费，验证首页不会拿余额冒充所得。
                var localCalendar = calendar
                localCalendar.timeZone = timeZone
                guard let yesterday = localCalendar.date(byAdding: .day, value: -1, to: now) else {
                    throw RewardLedgerError.invalidTimestamp
                }
                let ledger = RewardLedgerService(context: context)
                _ = try ledger.grantReward(sourceID: templateID, xp: 20, coins: 10, at: yesterday)
                _ = try ledger.grantReward(sourceID: taskID, xp: 11, coins: 7, at: now)
                _ = try ledger.spendCoins(sourceID: taskID, cost: 3, at: now)
            }
            if scenario == .corruptRewardLedger {
                // 仅 Debug 独占夹具故意缺少 Coin 伙伴，验证资产错误不隐藏任务；不是生产发奖入口。
                context.insert(
                    XPTransaction(
                        businessKey: RewardLedgerKey.xpReward(taskID), sourceID: taskID,
                        kind: .reward, amount: 11, createdAt: now))
                try context.save()
            }
            if scenario == .returnedSubmission, !shouldSeedTemplateOnly {
                // 用真实提交/退回事务构造状态，不手工伪造审计或金额。
                let row = try TaskSubmissionService(context: context).submit(occurrence, at: now)
                _ = try TaskSubmissionReviewService(context: context).returnForRevision(
                    occurrence, submissionID: row.submissionID, at: now)
            }
        }

        private static func removeAllData(from context: ModelContext) throws {
            // 先删除关系叶子，再删除实例和模板，避免让级联删除顺序影响测试重置的确定性。
            // 固定任务 ID 会复用，必须同步清理 V1 审计/账本，且只作用于显式隔离 UI 容器。
            try context.fetch(FetchDescriptor<PetFeeding>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<PetGrowthCheckpoint>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TaskSubmission>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<XPTransaction>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CoinTransaction>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<NotificationLink>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CompletionRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TimerSession>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TaskOccurrence>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ReminderRule>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TaskTemplate>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<DayOverride>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<AppSettings>()).forEach(context.delete)
            // 新增资料同样属于隔离测试状态；正式库不调用此重置，跨进程恢复不传reset。
            try context.fetch(FetchDescriptor<ChildProfile>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<Pet>()).forEach(context.delete)
            try context.save()
        }
    }
#endif
