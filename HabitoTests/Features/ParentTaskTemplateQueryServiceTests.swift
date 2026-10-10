import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("家长模板列表查询")
@MainActor
struct ParentTaskTemplateQueryServiceTests {
    @Test("首次设置保存后跳过添加，打开提醒后结束引导")
    func setupGuideAdvancesUsingSavedFacts() throws {
        let fixture = try Fixture()
        let model = ParentTaskTemplateListViewModel(
            context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: fixture.now))
        model.load()
        #expect(model.showsSetupGuide)
        #expect(!model.setupHasTask)
        _ = fixture.addTemplate(title: "阅读")
        try fixture.context.save()
        model.load()
        #expect(model.showsSetupGuide)
        #expect(model.setupHasTask)
        model.finishSetupGuide()
        model.load()
        #expect(!model.showsSetupGuide)
        let restarted = ParentTaskTemplateListViewModel(
            context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: fixture.now))
        restarted.load()
        #expect(!restarted.showsSetupGuide)
    }

    @Test("归档家庭的空列表不展示首次步骤")
    func archivedConfigurationDoesNotShowSetup() throws {
        let fixture = try Fixture()
        _ = fixture.addTemplate(title: "旧任务", archivedAt: fixture.now)
        try fixture.context.save()
        let model = ParentTaskTemplateListViewModel(
            context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: fixture.now))
        model.load()
        #expect(!model.showsSetupGuide)
        #expect(model.setupHasTask)
    }

    @Test("空存储返回空列表")
    func emptyStore() throws {
        let fixture = try Fixture()
        #expect(try fixture.items().isEmpty)
    }

    @Test("过滤归档并按启用状态和下一次计划排序")
    func filtersAndSorts() throws {
        let fixture = try Fixture()
        let later = try fixture.addWeekly(
            title: "明天任务",
            weekdays: [.thursday],
            minutes: 9 * 60
        )
        let sooner = try fixture.addWeekly(
            title: "今天任务",
            weekdays: [.wednesday],
            minutes: 13 * 60
        )
        let disabled = try fixture.addWeekly(
            title: "停用任务",
            weekdays: [.wednesday],
            minutes: 14 * 60,
            isEnabled: false
        )
        _ = try fixture.addWeekly(
            title: "已归档",
            weekdays: [.wednesday],
            minutes: 15 * 60,
            archivedAt: fixture.now
        )

        let items = try fixture.items()
        let expectedSooner = try fixture.date("2026-09-23T05:00:00Z")
        let expectedLater = try fixture.date("2026-09-24T01:00:00Z")

        #expect(items.map(\.id) == [sooner.id, later.id, disabled.id])
        #expect(items[0].nextScheduledAt == expectedSooner)
        #expect(items[1].nextScheduledAt == expectedLater)
        #expect(items[2].nextScheduledAt == nil)
        #expect(items[2].lifecycleState == .disabled)
    }

    @Test("当天时间已过时滚动到下周且过期一次性任务无后续计划")
    func rollsForwardAndExpires() throws {
        let fixture = try Fixture()
        let weekly = try fixture.addWeekly(
            title: "下周任务",
            weekdays: [.wednesday],
            minutes: 11 * 60
        )
        let expiredDate = try LocalDate(dateKey: "2026-09-22")
        let expired = fixture.addTemplate(title: "已过期")
        let expiredRule = ReminderRule(
            taskTemplateID: expired.id,
            recurrence: .once(on: expiredDate),
            timeOfDayMinutes: 9 * 60
        )
        fixture.context.insert(expiredRule)
        expired.reminderRule = expiredRule
        expiredRule.taskTemplate = expired

        let items = try fixture.items()
        let weeklyItem = try #require(items.first { $0.id == weekly.id })
        let expiredItem = try #require(items.first { $0.id == expired.id })
        let expectedNextWeek = try fixture.date("2026-09-30T03:00:00Z")
        #expect(weeklyItem.nextScheduledAt == expectedNextWeek)
        #expect(expiredItem.nextScheduledAt == nil)
    }

    @Test("损坏模板或规则不会被静默展示")
    func rejectsCorruptedData() throws {
        let fixture = try Fixture()
        _ = fixture.addTemplate(title: "")
        #expect(throws: ParentTaskTemplateQueryError.self) {
            try fixture.items()
        }
    }

    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let calendar: Calendar
        let timeZone: TimeZone
        let now: Date

        init() throws {
            container = try AppModelContainer.make(inMemory: true)
            context = container.mainContext
            calendar = Calendar(identifier: .gregorian)
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
        }

        func addWeekly(
            title: String,
            weekdays: Set<Weekday>,
            minutes: Int,
            isEnabled: Bool = true,
            archivedAt: Date? = nil
        ) throws -> TaskTemplate {
            let template = addTemplate(
                title: title,
                isEnabled: isEnabled,
                archivedAt: archivedAt
            )
            let rule = ReminderRule(
                taskTemplateID: template.id,
                recurrence: try .weekly(
                    on: weekdays,
                    starting: LocalDate(dateKey: "2026-09-01")
                ),
                timeOfDayMinutes: minutes
            )
            context.insert(rule)
            template.reminderRule = rule
            rule.taskTemplate = template
            return template
        }

        func addTemplate(
            title: String,
            isEnabled: Bool = true,
            archivedAt: Date? = nil
        ) -> TaskTemplate {
            let template = TaskTemplate(
                title: title,
                iconName: "book.fill",
                colorToken: "task",
                targetDurationSeconds: 900,
                isEnabled: isEnabled,
                createdAt: now,
                updatedAt: now,
                archivedAt: archivedAt
            )
            context.insert(template)
            return template
        }

        func items() throws -> [ParentTaskTemplateListItem] {
            try context.save()
            return try ParentTaskTemplateQueryService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ).items(at: now)
        }

        func date(_ value: String) throws -> Date {
            try Date(value, strategy: .iso8601)
        }
    }
}
