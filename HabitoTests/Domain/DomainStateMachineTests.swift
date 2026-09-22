import Testing
@testable import Habito

@Suite("领域状态机")
struct DomainStateMachineTests {
    @Test("待处理任务可以开始完成或跳过")
    func pendingOccurrenceSupportsItsThreeActions() throws {
        #expect(try TaskOccurrenceStatus.pending.applying(.start) == .inProgress)
        #expect(try TaskOccurrenceStatus.pending.applying(.complete) == .completed)
        #expect(try TaskOccurrenceStatus.pending.applying(.skip) == .skipped)
    }

    @Test("跳过恢复与完成撤销都回到待处理")
    func reversibleOccurrenceActionsReturnToPending() throws {
        #expect(try TaskOccurrenceStatus.skipped.applying(.restore) == .pending)
        #expect(try TaskOccurrenceStatus.completed.applying(.undoCompletion) == .pending)
    }

    @Test("进行中任务不能直接跳过")
    func inProgressOccurrenceRejectsSkip() {
        #expect(
            throws: DomainStateTransitionError(state: "inProgress", action: "skip")
        ) {
            try TaskOccurrenceStatus.inProgress.applying(.skip)
        }
    }

    @Test("计时可暂停继续并从活动状态结束")
    func timerSupportsPauseResumeAndEnd() throws {
        #expect(try TimerSessionState.running.applying(.pause) == .paused)
        #expect(try TimerSessionState.paused.applying(.resume) == .running)
        #expect(try TimerSessionState.running.applying(.end) == .ended)
        #expect(try TimerSessionState.paused.applying(.end) == .ended)
    }

    @Test("结束的计时会话不可复活")
    func endedTimerIsTerminal() {
        #expect(
            throws: DomainStateTransitionError(state: "ended", action: "resume")
        ) {
            try TimerSessionState.ended.applying(.resume)
        }
    }

    @Test("模板可停用再启用且可从活动状态软删除")
    func templateSupportsDisableEnableAndArchive() throws {
        #expect(try TaskTemplateLifecycleState.active.applying(.disable) == .disabled)
        #expect(try TaskTemplateLifecycleState.disabled.applying(.enable) == .active)
        #expect(try TaskTemplateLifecycleState.active.applying(.archive) == .archived)
        #expect(try TaskTemplateLifecycleState.disabled.applying(.archive) == .archived)
    }

    @Test("软删除模板是不可恢复终态")
    func archivedTemplateIsTerminal() {
        #expect(
            throws: DomainStateTransitionError(state: "archived", action: "enable")
        ) {
            try TaskTemplateLifecycleState.archived.applying(.enable)
        }
    }

    @Test("单日覆盖不接收后续模板更新")
    func detachedOverrideIsProtectedFromTemplateUpdates() {
        #expect(TaskOccurrenceOrigin.generated(templateRevision: 3).receivesTemplateUpdates)
        #expect(!TaskOccurrenceOrigin.detachedOverride.receivesTemplateUpdates)
    }
}
