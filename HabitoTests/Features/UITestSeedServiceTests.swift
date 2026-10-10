#if DEBUG
    import Foundation
    import SwiftData
    import Testing
    @testable import Habito

    /// 验证 Debug 夹具的隔离与重启语义，避免测试播种掩盖真实业务结果。
    @MainActor
    @Suite("UI 测试播种边界")
    struct UITestSeedServiceTests {
        @Test("仅模板与常规样例使用不同实例准备方式", arguments: [true, false])
        func initialSeedHasExpectedGraph(templateOnly: Bool) throws {
            let fixture = try Fixture()
            try fixture.prepare(templateOnly: templateOnly)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == (templateOnly ? 0 : 1))
            let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
            #expect(template.reminderRule?.taskTemplateID == template.id)
            #expect(template.reminderRule?.taskTemplate === template)
        }

        @Test("停用或归档清理样例实例后，重启播种不得重新启用模板", arguments: [TaskTemplateLifecycleAction.disable, .archive])
        func templateMaintenanceSurvivesRelaunchSeed(action: TaskTemplateLifecycleAction) throws {
            let fixture = try Fixture()
            try fixture.prepare()
            let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
            _ = try TaskTemplateLifecycleService(
                context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone
            ).perform(
                templateID: template.id, action: action,
                today: LocalDate(dateKey: "2026-09-27"), now: fixture.now)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
            try fixture.prepare()
            #expect(template.lifecycleState == (action == .disable ? .disabled : .archived))
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        }

        @Test("重复播种不覆盖完成历史或创建第二份任务")
        func repeatedSeedPreservesCompletionHistory() throws {
            let fixture = try Fixture()
            try fixture.prepare()
            let occurrence = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            _ = try TaskProgressService(context: fixture.context).complete(
                occurrence, at: fixture.now, source: .childManual)
            try fixture.prepare()
            #expect(occurrence.status == .completed)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        }

        @Test("仅模板夹具重复准备仍无实例，不替正式重建预先造数据")
        func repeatedTemplateOnlySeedDoesNotMaterializeOccurrences() throws {
            let fixture = try Fixture()
            try fixture.prepare(templateOnly: true)
            try fixture.prepare(templateOnly: true)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        }

        @Test("显式场景只写入合成配置，提交和退回均不提前发奖", arguments: UITestTaskScenario.allCases)
        func explicitScenarioHasExpectedConfiguration(scenario: UITestTaskScenario) throws {
            let fixture = try Fixture()
            try fixture.prepare(scenario: scenario)
            let occurrence = try #require(
                fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.id == UITestSeedService.taskID })
            #expect(occurrence.verificationTypeSnapshot == scenario.verificationType)
            #expect(
                scenario.hasSyntheticReward
                    == (scenario == .rewardSelfConfirm || scenario == .rewardAfterReminder
                        || scenario == .parentApproval
                        || scenario == .returnedSubmission || scenario == .dailyIncome || scenario == .petCare
                        || scenario == .targetReachedSelfConfirm || scenario == .targetReachedParentApproval))
            #expect(occurrence.xpRewardSnapshot == (scenario.hasSyntheticReward ? 11 : 0))
            #expect(occurrence.coinRewardSnapshot == (scenario.hasSyntheticReward ? 7 : 0))
            #expect(occurrence.activeBonusCoinSnapshot == (scenario.hasSyntheticReward ? 3 : 0))
            #expect(occurrence.scheduledAt == fixture.now.addingTimeInterval(scenario.reminderOffset))
            let submissions = try fixture.context.fetch(FetchDescriptor<TaskSubmission>())
            #expect(submissions.count == (scenario == .returnedSubmission ? 1 : 0))
            if scenario == .returnedSubmission {
                #expect(submissions.first?.reviewState == .returned)
            }
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            if scenario == .taskSwitch {
                let second = try #require(
                    fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first {
                        $0.id == UITestSeedService.secondaryTaskID
                    })
                #expect(second.status == .inProgress)
                let session = try #require(
                    fixture.context.fetch(FetchDescriptor<TimerSession>()).first { $0.occurrenceID == second.id })
                #expect(session.state == .running && session.startedAt == fixture.now.addingTimeInterval(-120))
                #expect(occurrence.status == .pending)
            }

            if scenario == .targetReachedSelfConfirm || scenario == .targetReachedParentApproval {
                let session = try #require(fixture.context.fetch(FetchDescriptor<TimerSession>()).first)
                #expect(session.state == .running)
                #expect(session.startedAt == fixture.now.addingTimeInterval(-occurrence.targetDurationSnapshot))
            }
            #expect(
                try fixture.context.fetchCount(FetchDescriptor<XPTransaction>())
                    == (scenario == .dailyIncome
                        ? 2 : (scenario == .corruptRewardLedger || scenario == .petCare ? 1 : 0)))
            #expect(
                try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>())
                    == (scenario == .dailyIncome ? 3 : (scenario == .petCare ? 1 : 0))
            )
        }

        @Test("重启保留退回审计，不重播夹具或改回旧零奖励配置")
        func returnedScenarioSurvivesRelaunchWithoutReseeding() throws {
            let fixture = try Fixture()
            try fixture.prepare(scenario: .returnedSubmission)
            let originalRows = try fixture.context.fetch(FetchDescriptor<TaskSubmission>())
            let originalID = try #require(originalRows.first?.id)
            try fixture.prepare()
            let rows = try fixture.context.fetch(FetchDescriptor<TaskSubmission>())
            #expect(rows.count == 1)
            #expect(rows.first?.id == originalID)
            #expect(rows.first?.reviewState == .returned)
            let occurrence = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            #expect(occurrence.verificationTypeSnapshot == .parentApproval)
            #expect(occurrence.xpRewardSnapshot == 11)
        }

        @Test("隔离重置同时清理审核审计和奖励账本", arguments: [true, false])
        func resetRemovesAllV1History(approve: Bool) throws {
            let fixture = try Fixture()
            try fixture.prepare(scenario: .parentApproval)
            let occurrence = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            let submission = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
            if approve {
                _ = try TaskSubmissionReviewService(context: fixture.context).approve(
                    occurrence, submissionID: submission.submissionID, at: fixture.now)
                #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
                #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 1)
            }
            try fixture.prepare(reset: true)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
            let newOccurrence = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            #expect(newOccurrence.status == .pending)
            #expect(newOccurrence.xpRewardSnapshot == 0)
        }

        @Test("缺省场景兼容旧用例，显式场景严格解析", arguments: UITestTaskScenario.allCases)
        func scenarioArgumentsParse(scenario: UITestTaskScenario) throws {
            #expect(try UITestTaskScenario.parse(arguments: []) == .legacy)
            #expect(
                try UITestTaskScenario.parse(arguments: [UITestTaskScenario.argument, scenario.rawValue]) == scenario)
        }

        @Test(
            "缺失或未知场景参数明确失败，不悄悄退回其他容器",
            arguments: [
                ["--habito-ui-task-scenario"], ["--habito-ui-task-scenario", "unknown"],
            ])
        func invalidScenarioArgumentsAreRejected(arguments: [String]) {
            #expect(throws: CocoaError.self) {
                try UITestTaskScenario.parse(arguments: arguments)
            }
        }

        @Test("名字在跨进程准备时保留，显式空库重置才清理", arguments: [false, true])
        func namesSurviveRecoveryButNotExplicitReset(reset: Bool) throws {
            let fixture = try Fixture()
            try fixture.prepare()
            let names = try FamilyProfileNames(childNickname: "合成播种孩子", petName: "合成播种小狗")
            let service = FamilyProfileService(context: fixture.context)
            try service.save(names)
            try UITestSeedService.prepare(
                container: fixture.container, shouldReset: reset, shouldSeedSampleData: false,
                now: fixture.now, calendar: fixture.calendar, timeZone: fixture.timeZone)
            #expect(try service.load() == (reset ? nil : names))
            #expect(try fixture.context.fetchCount(FetchDescriptor<ChildProfile>()) == (reset ? 0 : 1))
            #expect(try fixture.context.fetchCount(FetchDescriptor<Pet>()) == (reset ? 0 : 1))
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == (reset ? 0 : 1))
            #expect(!fixture.context.hasChanges)
        }

        private struct Fixture {
            let container: ModelContainer
            let now: Date
            let calendar = Calendar(identifier: .gregorian)
            let timeZone: TimeZone
            var context: ModelContext { container.mainContext }

            init() throws {
                container = try AppModelContainer.make(inMemory: true)
                now = try Date("2026-09-27T02:00:00Z", strategy: .iso8601)
                timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            }

            func prepare(templateOnly: Bool = false, reset: Bool = false, scenario: UITestTaskScenario = .legacy) throws
            {
                try UITestSeedService.prepare(
                    container: container, shouldReset: reset, shouldSeedTemplateOnly: templateOnly,
                    now: now, calendar: calendar, timeZone: timeZone, scenario: scenario)
            }
        }
    }
#endif
