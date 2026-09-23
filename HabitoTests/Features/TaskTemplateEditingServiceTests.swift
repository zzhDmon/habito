import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("任务模板编辑事务")
@MainActor
struct TaskTemplateEditingServiceTests {
    @Test("创建每天十九点半阅读十五分钟并可重载为草稿")
    func createsAndReloadsDailyReading() throws {
        let fixture = try Fixture()
        var draft = TaskTemplateDraft.new
        draft.title = "  阅读 15 分钟  "

        let id = try fixture.service.save(draft, at: fixture.now)
        let templates = try fixture.context.fetch(FetchDescriptor<TaskTemplate>())
        let template = try #require(templates.first)
        let rule = try #require(template.reminderRule)
        let recurrence = try rule.decodedRecurrence()
        let expectedStartDate = try LocalDate(dateKey: "2026-09-23")

        #expect(templates.count == 1)
        #expect(template.id == id)
        #expect(template.title == "阅读 15 分钟")
        #expect(template.targetDurationSeconds == 900)
        #expect(template.revision == 1)
        #expect(rule.timeOfDayMinutes == 19 * 60 + 30)
        #expect(recurrence.weekdays == Set(Weekday.allCases))
        #expect(recurrence.startDate == expectedStartDate)

        let loaded = try fixture.service.load(templateID: id)
        #expect(loaded.templateID == id)
        #expect(loaded.title == "阅读 15 分钟")
        #expect(loaded.targetDurationMinutes == 15)
        #expect(loaded.timeOfDayMinutes == 19 * 60 + 30)
        #expect(loaded.weekdays == Set(Weekday.allCases))
        #expect(loaded.isEnabled)
    }

    @Test("编辑沿用稳定 ID 和生效范围并递增修订")
    func editsExistingTemplate() throws {
        let fixture = try Fixture()
        var initial = TaskTemplateDraft.new
        initial.title = "阅读"
        let id = try fixture.service.save(initial, at: fixture.now)
        let original = try fixture.service.load(templateID: id)

        var edited = original
        edited.title = "晚间阅读"
        edited.timeOfDayMinutes = 20 * 60
        edited.targetDurationMinutes = 25
        edited.weekdays = [.monday, .friday]
        edited.isEnabled = false
        let updatedAt = fixture.now.addingTimeInterval(60)
        let savedID = try fixture.service.save(edited, at: updatedAt)

        let template = try #require(
            fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first
        )
        let rule = try #require(template.reminderRule)
        let recurrence = try rule.decodedRecurrence()
        let expectedStartDate = try LocalDate(dateKey: "2026-09-23")
        #expect(savedID == id)
        #expect(template.title == "晚间阅读")
        #expect(template.targetDurationSeconds == 1_500)
        #expect(template.revision == 2)
        #expect(template.updatedAt == updatedAt)
        #expect(!template.isEnabled)
        #expect(rule.timeOfDayMinutes == 20 * 60)
        #expect(!rule.isEnabled)
        #expect(recurrence.weekdays == Set([Weekday.monday, .friday]))
        #expect(recurrence.startDate == expectedStartDate)
    }

    @Test("非法输入在写模型前被拒绝")
    func rejectsInvalidDraftBeforeWriting() throws {
        let fixture = try Fixture()
        var draft = TaskTemplateDraft.new
        draft.title = "   "
        #expect(throws: TaskTemplateEditorError.titleRequired) {
            try fixture.service.save(draft, at: fixture.now)
        }

        draft.title = "阅读"
        draft.weekdays = []
        #expect(throws: TaskTemplateEditorError.noWeekdays) {
            try fixture.service.save(draft, at: fixture.now)
        }

        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 0)
    }

    @Test("归档模板不能通过编辑入口复活")
    func rejectsArchivedTemplate() throws {
        let fixture = try Fixture()
        var draft = TaskTemplateDraft.new
        draft.title = "阅读"
        let id = try fixture.service.save(draft, at: fixture.now)
        let template = try #require(
            fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first
        )
        template.archivedAt = fixture.now
        try fixture.context.save()

        #expect(throws: TaskTemplateEditorError.archivedTemplate(id)) {
            try fixture.service.load(templateID: id)
        }
    }

    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let service: TaskTemplateEditingService
        let now: Date

        init() throws {
            container = try AppModelContainer.make(inMemory: true)
            context = container.mainContext
            let calendar = Calendar(identifier: .gregorian)
            let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            service = TaskTemplateEditingService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            )
            now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
        }
    }
}
