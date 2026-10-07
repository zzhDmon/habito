import Testing
@testable import Habito

struct TodayCompletionSummaryTests {
    @Test("正数全部确认完成才生成真实数量", arguments: [1, 3, 100])
    func confirmedCompletionKeepsCount(count: Int) throws {
        let summary = try #require(
            TodayCompletionSummary(completedCount: count, totalCount: count, isAllCompleted: true))
        #expect(summary.completedCount == count)
    }

    @Test("无任务或全跳过不是通关", arguments: [false, true])
    func zeroDenominatorNeverCelebrates(flag: Bool) {
        #expect(TodayCompletionSummary(completedCount: 0, totalCount: 0, isAllCompleted: flag) == nil)
    }

    @Test("矛盾或负数计数拒绝生成结果", arguments: [-1, 0, 1, 3])
    func invalidCountsDoNotInventCompletion(completed: Int) {
        #expect(TodayCompletionSummary(completedCount: completed, totalCount: 2, isAllCompleted: true) == nil)
        #expect(TodayCompletionSummary(completedCount: completed, totalCount: -1, isAllCompleted: true) == nil)
    }

    @Test("待验收跨日或撤销导致查询未全完成时不能只看比例")
    func queryFlagMustAlsoConfirmCompletion() {
        #expect(TodayCompletionSummary(completedCount: 1, totalCount: 1, isAllCompleted: false) == nil)
        #expect(TodayScreenContent.previewCarryOver.dailyCompletion == nil)
        #expect(TodayScreenContent.preview.dailyCompletion == nil)
    }

    @Test("重新投影同一完成事实仅重复读取，不产生新的结果事件")
    func repeatReadProducesSameValue() {
        let first = TodayScreenContent.previewCompleted.dailyCompletion
        let reloaded = TodayScreenContent(
            recommendedTask: nil, remainingTasks: [.previewCompleted],
            completedCount: 1, totalCount: 1, isAllCompleted: true
        ).dailyCompletion
        #expect(first == reloaded)
    }
}
