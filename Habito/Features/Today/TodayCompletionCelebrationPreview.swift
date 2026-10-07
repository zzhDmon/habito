import Foundation

/// 仅提供固定合成纯值，不创建容器或写入正式任务，Preview与原生渲染测试共用。
@MainActor
enum TodayCompletionCelebrationPreview {
    static var event: TodayCompletionCelebrationEvent? {
        do {
            let date = try LocalDate(year: 2026, month: 10, day: 7)
            let completionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
            let task = TodayTaskItem(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)), date: date,
                scheduledAt: .distantPast, title: "合成任务", iconName: "book", colorToken: "reading",
                targetDurationSeconds: 60, status: .completed, origin: .generated(templateRevision: 1),
                activeSessionState: nil, activeDurationSeconds: 0,
                completion: TodayTaskCompletion(
                    id: completionID, completedAt: .distantPast, activeDurationSeconds: 0, source: .childManual))
            let snapshot = TodayTasksSnapshot(
                date: date, isCurrentDate: true, tasks: [task], carryOverTasks: [], recommendedTaskID: nil,
                completedCount: 1, totalCount: 1)
            let result = TaskCompletionResult(
                completionID: completionID, completedAt: .distantPast, timing: .unknown, xp: 0, coins: 0,
                didComplete: true)
            return TodayCompletionCelebrationEvent(completion: result, snapshot: snapshot)
        } catch {
            // 固定预览日期意外失效是开发配置问题，不忽略为正式业务成功或替家庭填入数据。
            assertionFailure("固定通关预览日期不合法")
            return nil
        }
    }
}
