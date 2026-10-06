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
