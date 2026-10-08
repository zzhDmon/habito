import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("任务编辑器显式配置与通知权限接入")
@MainActor
struct TaskTemplateEditorViewModelTests {
    @Test("首次保存等待用户授权返回后再次重建，不依赖通知弹窗切换前后台")
    func firstAuthorizationResponseRequestsFreshRebuild() async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "首次提醒"
        var revisionWhileAwaiting: Int?
        fixture.provider.onRequestAuthorization = {
            revisionWhileAwaiting = fixture.rebuildTrigger.revision
            let templateCount = try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>())
            #expect(templateCount == 1)
            #expect(fixture.provider.currentAuthorizationState == .notDetermined)
            // 授权等待会让主 actor 接受新意图；重复保存不能把仍打开的新建草稿再写一份。
            #expect(fixture.model.isSaving)
            #expect(await fixture.model.save() == .failed)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(fixture.rebuildTrigger.revision == 1 && fixture.model.feedback == nil)
        }
        let outcome = await fixture.model.save()
        #expect(outcome == .saved)
        #expect(revisionWhileAwaiting == 1)
        #expect(fixture.provider.currentAuthorizationState == .authorized)
        #expect(fixture.rebuildTrigger.revision == 2)
    }

    @Test("权限已拒绝仍保存任务且不重复请求")
    func deniedPermissionDoesNotBlockSave() async throws {
        let fixture = try makeFixture()
        fixture.provider.currentAuthorizationState = .denied
        fixture.model.load()
        fixture.model.draft.title = "阅读"

        let outcome = await fixture.model.save()

        #expect(outcome == .saved)
        #expect(fixture.provider.requestCount == 0)
        #expect(fixture.rebuildTrigger.revision == 2)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    }

    @Test("系统权限调用失败时任务保留并返回可见警告")
    func permissionFailureKeepsSavedTask() async throws {
        let fixture = try makeFixture()
        fixture.provider.requestError = NSError(domain: "NotificationPermissionTest", code: 1)
        fixture.model.load()
        fixture.model.draft.title = "写字"

        let outcome = await fixture.model.save()

        #expect(outcome == .savedWithNotificationWarning)
        #expect(fixture.rebuildTrigger.revision == 2)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    }

    @Test("坏奖励原文保留且不写入、不请求权限或通知重建", arguments: ["", "-1", "1.5", "abc", "１２", "9999999999999999999999"], [0, 1, 2])
    func invalidRewardTextDoesNotSave(text: String, field: Int) async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "输入校验"
        switch field {
        case 0: fixture.model.rewardInput.xp = text
        case 1: fixture.model.rewardInput.baseCoins = text
        default: fixture.model.rewardInput.autonomyCoins = text
        }
        let originalInput = fixture.model.rewardInput
        #expect(await fixture.model.save() == .failed)
        #expect(fixture.model.feedback == .validation(.invalidRewardInput))
        #expect(fixture.model.rewardInput == originalInput)
        #expect(
            fixture.model.draft.xpReward == 0 && fixture.model.draft.coinReward == 0
                && fixture.model.draft.activeBonusCoin == 0)
        #expect(fixture.rebuildTrigger.revision == 0 && fixture.provider.requestCount == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(!fixture.context.hasChanges && !fixture.model.isSaving)
        fixture.model.rewardInput = TaskTemplateRewardInput(draft: .new)
        #expect(await fixture.model.save() == .saved)
    }

    @Test("原始输入显式保存、编辑回读与重复加载不覆盖用户输入", arguments: TaskVerificationType.allCases, [false, true])
    func savesAndReloadsExplicitConfiguration(verification: TaskVerificationType, zero: Bool) async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "正式页面配置"
        fixture.model.draft.category = .challenge
        fixture.model.draft.timePeriod = .afterSchool
        fixture.model.draft.verificationType = verification
        fixture.model.rewardInput.xp = zero ? "0" : " 0011 "
        fixture.model.rewardInput.baseCoins = zero ? "0" : "7"
        fixture.model.rewardInput.autonomyCoins = zero ? "0" : "3"
        #expect(await fixture.model.save() == .saved)
        let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
        let editing = try makeFixture(context: fixture.context, templateID: template.id)
        editing.model.load()
        #expect(editing.model.draft.category == .challenge && editing.model.draft.timePeriod == .afterSchool)
        #expect(editing.model.draft.verificationType == verification)
        #expect(editing.model.rewardInput.xp == (zero ? "0" : "11"))
        #expect(editing.model.rewardInput.baseCoins == (zero ? "0" : "7"))
        #expect(editing.model.rewardInput.autonomyCoins == (zero ? "0" : "3"))
        editing.model.rewardInput.xp = "尚未保存"
        editing.model.load()
        #expect(editing.model.rewardInput.xp == "尚未保存")
        editing.model.rewardInput.xp = zero ? "0" : "11"
        editing.model.draft.title = "只改标题"
        #expect(await editing.model.save() == .saved)
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        #expect(row.verificationTypeSnapshot == verification)
        #expect(row.xpRewardSnapshot == (zero ? 0 : 11) && row.coinRewardSnapshot == (zero ? 0 : 7))
        #expect(row.activeBonusCoinSnapshot == (zero ? 0 : 3))
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
    }

    @Test("编辑页面状态保存/回读可空分钟，重复加载不覆盖未保存输入", arguments: [false, true])
    func viewModelKeepsOptionalTimeDraft(isDeadline: Bool) async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "可空时间"
        fixture.model.draft.plannedTimeOfDayMinutes = isDeadline ? nil : 480
        fixture.model.draft.deadlineTimeOfDayMinutes = isDeadline ? 1320 : nil
        #expect(await fixture.model.save() == .saved)
        let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
        let editing = try makeFixture(context: fixture.context, templateID: template.id)
        editing.model.load()
        #expect(editing.model.draft.plannedTimeOfDayMinutes == fixture.model.draft.plannedTimeOfDayMinutes)
        #expect(editing.model.draft.deadlineTimeOfDayMinutes == fixture.model.draft.deadlineTimeOfDayMinutes)
        editing.model.draft.plannedTimeOfDayMinutes = 600
        editing.model.load()
        #expect(editing.model.draft.plannedTimeOfDayMinutes == 600)
        editing.model.draft.plannedTimeOfDayMinutes = nil
        editing.model.draft.deadlineTimeOfDayMinutes = nil
        #expect(await editing.model.save() == .saved)
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        #expect(row.plannedAt == nil && row.deadlineAt == nil)
        #expect(
            template.reminderRule?.plannedTimeOfDayMinutes == nil
                && template.reminderRule?.deadlineTimeOfDayMinutes == nil)
    }

    @Test("编辑页面坏可空分钟保留输入且不请求权限或重建", arguments: [-1, 1440], [false, true])
    func invalidOptionalDraftCannotSaveOrTrigger(value: Int, isDeadline: Bool) async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "不能保存坏时间"
        if isDeadline {
            fixture.model.draft.deadlineTimeOfDayMinutes = value
        } else {
            fixture.model.draft.plannedTimeOfDayMinutes = value
        }
        #expect(await fixture.model.save() == .failed)
        #expect(fixture.model.feedback == .validation(.invalidTime))
        #expect(
            (isDeadline ? fixture.model.draft.deadlineTimeOfDayMinutes : fixture.model.draft.plannedTimeOfDayMinutes)
                == value)
        #expect(
            fixture.provider.requestCount == 0 && fixture.rebuildTrigger.revision == 0 && !fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
    }

    @Test("尚未加载不能保存，加载后可正常创建")
    func saveBeforeLoadCannotCreateTemplate() async throws {
        let fixture = try makeFixture()
        fixture.model.draft.title = "加载未完成"
        #expect(await fixture.model.save() == .failed)
        #expect(fixture.model.isLoading && !fixture.model.isSaving && fixture.model.feedback == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(fixture.rebuildTrigger.revision == 0 && fixture.provider.requestCount == 0)
        fixture.model.load()
        #expect(await fixture.model.save() == .saved)
    }

    @Test("坏配置载入失败后不能将空白草稿另存成新任务")
    func failedLoadCannotCreateAnotherTemplate() async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "原有模板"
        #expect(await fixture.model.save() == .saved)
        let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
        template.categoryRawValue = "corrupt"
        try fixture.context.save()
        let editing = try makeFixture(context: fixture.context, templateID: template.id)
        editing.model.load()
        #expect(editing.model.hasLoadFailure && !editing.model.isLoading)
        editing.model.draft.title = "不能另存"
        #expect(await editing.model.save() == .failed)
        #expect(editing.model.feedback == .loadFailure && !editing.model.isSaving)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
        #expect(template.title == "原有模板" && template.categoryRawValue == "corrupt")
        #expect(editing.rebuildTrigger.revision == 0 && editing.provider.requestCount == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("原文接受安全整数边界并一次性转成纯值草稿")
    func rawInputAcceptsIntegerBoundaryWithoutChangingSource() throws {
        var draft = TaskTemplateDraft.new
        draft.xpReward = 11
        var input = TaskTemplateRewardInput(draft: draft)
        input.xp = String(Int.max)
        input.baseCoins = " 0007\n"
        input.autonomyCoins = "0"
        let parsed = try input.applying(to: draft)
        #expect(parsed.xpReward == Int.max && parsed.coinReward == 7 && parsed.activeBonusCoin == 0)
        #expect(draft.xpReward == 11 && draft.coinReward == 0 && draft.activeBonusCoin == 0)
    }

    @Test("金币加总溢出和保存失败保持输入且不发成功事件", arguments: [false, true])
    func failureKeepsInputWithoutSuccess(failsStorage: Bool) async throws {
        let fixture = try makeFixture(failsStorage: failsStorage)
        fixture.model.load()
        fixture.model.draft.title = "失败可纠正"
        fixture.model.rewardInput.xp = "11"
        fixture.model.rewardInput.baseCoins = failsStorage ? "7" : String(Int.max)
        fixture.model.rewardInput.autonomyCoins = "3"
        let originalInput = fixture.model.rewardInput
        #expect(await fixture.model.save() == .failed)
        #expect(fixture.model.feedback == (failsStorage ? .storageFailure : .validation(.rewardOverflow)))
        #expect(fixture.model.rewardInput == originalInput)
        #expect(fixture.rebuildTrigger.revision == 0 && fixture.provider.requestCount == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("旧空值不会启用，显式开启采用可见提醒候选，关闭独立清空", arguments: [false, true], [false, true])
    func optionalTimeControlsStayExplicit(plan: Bool, deadline: Bool) async throws {
        let fixture = try makeFixture()
        let model = fixture.model
        model.load()
        model.draft.title = "明确开启时间"
        #expect(!model.isPlannedTimeEnabled && !model.isDeadlineTimeEnabled)
        var calendar = model.timeInputCalendar
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        model.scheduledTime = try #require(
            calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 16, minute: 20)))
        model.isPlannedTimeEnabled = plan
        model.isDeadlineTimeEnabled = deadline
        #expect(model.draft.plannedTimeOfDayMinutes == (plan ? 980 : nil))
        #expect(model.draft.deadlineTimeOfDayMinutes == (deadline ? 980 : nil))
        #expect(await model.save() == .saved)
        let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
        let editing = try makeFixture(context: fixture.context, templateID: template.id)
        editing.model.load()
        #expect(editing.model.isPlannedTimeEnabled == plan && editing.model.isDeadlineTimeEnabled == deadline)
        editing.model.isPlannedTimeEnabled = false
        #expect(editing.model.draft.plannedTimeOfDayMinutes == nil)
        #expect(editing.model.draft.deadlineTimeOfDayMinutes == (deadline ? 980 : nil))
        editing.model.isDeadlineTimeEnabled = false
        #expect(await editing.model.save() == .saved)
        #expect(template.reminderRule?.timeOfDayMinutes == 980)
        #expect(
            template.reminderRule?.plannedTimeOfDayMinutes == nil
                && template.reminderRule?.deadlineTimeOfDayMinutes == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
    }

    @Test("日期控件转换只取注入时区时分，固定锚点回读和重复加载不丢输入", arguments: [0, 480, 980, 1439], [false, true])
    func timeControlsRoundTripFixedMinutes(minutes: Int, deadline: Bool) async throws {
        let fixture = try makeFixture()
        let model = fixture.model
        model.load()
        model.draft.title = "分钟边界"
        let calendar = model.timeInputCalendar
        // 选取另一年/月的控件日期，证明日期部分不会成为任务的业务日期。
        let selection = try #require(
            calendar.date(from: DateComponents(year: 2012, month: 2, day: 29, hour: minutes / 60, minute: minutes % 60))
        )
        if deadline { model.deadlineTime = selection } else { model.plannedTime = selection }
        model.load()
        let selected = deadline ? model.deadlineTime : model.plannedTime
        #expect(calendar.component(.year, from: selected) == 2001)
        #expect(calendar.component(.hour, from: selected) * 60 + calendar.component(.minute, from: selected) == minutes)
        #expect((deadline ? model.draft.deadlineTimeOfDayMinutes : model.draft.plannedTimeOfDayMinutes) == minutes)
        #expect(await model.save() == .saved)
        let rule = try #require(fixture.context.fetch(FetchDescriptor<ReminderRule>()).first)
        #expect((deadline ? rule.deadlineTimeOfDayMinutes : rule.plannedTimeOfDayMinutes) == minutes)
        #expect((deadline ? rule.plannedTimeOfDayMinutes : rule.deadlineTimeOfDayMinutes) == nil)
        #expect(rule.timeOfDayMinutes == 1170)
    }

    @Test("非有限控件值明确校验失败而非变午夜，纠正后可保存", arguments: [Double.nan, Double.infinity, -Double.infinity], [0, 1, 2])
    func invalidDateControlCannotBecomeMidnight(value: Double, field: Int) async throws {
        let fixture = try makeFixture()
        let model = fixture.model
        model.load()
        model.draft.title = "坏控件值"
        let date = Date(timeIntervalSinceReferenceDate: value)
        switch field {
        case 0: model.scheduledTime = date
        case 1: model.plannedTime = date
        default: model.deadlineTime = date
        }
        #expect(await model.save() == .failed)
        #expect(model.feedback == .validation(.invalidTime))
        #expect(fixture.rebuildTrigger.revision == 0 && fixture.provider.requestCount == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(!fixture.context.hasChanges)
        if field == 0 { model.scheduledTime = Date(timeIntervalSinceReferenceDate: 0) }
        if field == 1 { model.isPlannedTimeEnabled = false }
        if field == 2 { model.isDeadlineTimeEnabled = false }
        #expect(await model.save() == .saved)
    }

    @Test("时间控件保存失败保留可见输入，无重建或半写")
    func timeControlFailureKeepsVisibleInput() async throws {
        let fixture = try makeFixture(failsStorage: true)
        let model = fixture.model
        model.load()
        model.draft.title = "失败保留时间"
        model.isPlannedTimeEnabled = true
        model.isDeadlineTimeEnabled = true
        model.plannedTime = model.scheduledTime.addingTimeInterval(-3600)
        model.deadlineTime = model.scheduledTime.addingTimeInterval(3600)
        #expect(await model.save() == .failed)
        #expect(model.feedback == .storageFailure)
        #expect(model.draft.plannedTimeOfDayMinutes == 1110 && model.draft.deadlineTimeOfDayMinutes == 1230)
        #expect(model.isPlannedTimeEnabled && model.isDeadlineTimeEnabled)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(
            !fixture.context.hasChanges && fixture.rebuildTrigger.revision == 0 && fixture.provider.requestCount == 0)
    }

    @Test("主动模板只填新建草稿，保留时间且无存储副作用", arguments: TaskLearningPreset.allCases)
    func presetChangesOnlyUnsavedDraft(preset: TaskLearningPreset) throws {
        let fixture = try makeFixture()
        let model = fixture.model
        model.applyLearningPreset(preset)
        #expect(model.draft.title.isEmpty)
        model.load()
        model.isPlannedTimeEnabled = true
        model.isDeadlineTimeEnabled = true
        let reminder = model.scheduledTime
        let planned = model.draft.plannedTimeOfDayMinutes
        let deadline = model.draft.deadlineTimeOfDayMinutes
        model.applyLearningPreset(preset)
        #expect(model.draft.title == preset.title)
        #expect(model.draft.weekdays == Weekday.schoolDays)
        #expect(model.scheduledTime == reminder)
        #expect(model.draft.plannedTimeOfDayMinutes == planned && model.draft.deadlineTimeOfDayMinutes == deadline)
        #expect(try model.rewardInput.applying(to: model.draft) == model.draft)
        #expect(!fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(fixture.rebuildTrigger.revision == 0 && fixture.provider.requestCount == 0)
        model.draft.title = "家长调整"
        model.rewardInput.xp = "17"
        model.load()
        #expect(model.draft.title == "家长调整" && model.rewardInput.xp == "17")
    }

    @Test("预设可调整后保存回读，旧任务拒绝再次套用")
    func presetPersistsCustomChoicesWithoutReplacingExistingTask() async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.applyLearningPreset(.reading)
        fixture.model.rewardInput.xp = "15"
        fixture.model.draft.weekdays = TaskWeekdayPreset.weekend.days
        #expect(await fixture.model.save() == .saved)
        let template = try #require(fixture.context.fetch(FetchDescriptor<TaskTemplate>()).first)
        let editing = try makeFixture(context: fixture.context, templateID: template.id)
        editing.model.load()
        #expect(editing.model.draft.title == TaskLearningPreset.reading.title)
        #expect(editing.model.draft.xpReward == 15 && editing.model.draft.coinReward == 2)
        #expect(editing.model.draft.activeBonusCoin == 1)
        #expect(editing.model.draft.weekdays == TaskWeekdayPreset.weekend.days)
        let before = editing.model.draft
        editing.model.applyLearningPreset(.mathHomework)
        #expect(editing.model.draft == before)
        #expect(!fixture.context.hasChanges)
    }

    private func makeFixture(
        context suppliedContext: ModelContext? = nil, templateID: UUID? = nil, failsStorage: Bool = false
    ) throws -> Fixture {
        let container = try AppModelContainer.make(inMemory: true)
        let context = suppliedContext ?? container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let provider = FakeLocalNotificationService()
        let rebuildTrigger = NotificationRebuildTrigger()
        let model = TaskTemplateEditorViewModel(
            templateID: templateID,
            service: TaskTemplateEditingService(
                context: context,
                calendar: calendar,
                timeZone: timeZone,
                saveChanges: { context in
                    if failsStorage { throw NSError(domain: "EditorStorageTest", code: 1) }
                    try context.save()
                }
            ),
            lifecycleService: TaskTemplateLifecycleService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ),
            notificationPermissionService: NotificationPermissionService(
                context: context,
                provider: provider
            ),
            notificationRebuildTrigger: rebuildTrigger,
            dateProvider: FixedDateProvider(value: Date(timeIntervalSince1970: 1_800_000_000)),
            calendar: calendar,
            timeZone: timeZone
        )
        return Fixture(
            container: container,
            context: context,
            provider: provider,
            rebuildTrigger: rebuildTrigger,
            model: model
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let provider: FakeLocalNotificationService
        let rebuildTrigger: NotificationRebuildTrigger
        let model: TaskTemplateEditorViewModel
    }
}
