#if DEBUG
    import Foundation
    import Testing
    @testable import Habito

    /// 固定合成事务验证双标志隔离，不读取正式家庭数据或真实时钟。
    @Suite("今日仪式失败探针隔离")
    @MainActor
    struct UITestTodayViewModelFactoryTests {
        @Test("仅隔离和故障双标志同时启用才失败", arguments: [false, true], [false, true])
        func failureRequiresBothFlags(isolated: Bool, failure: Bool) throws {
            let fixture = try TodayQueryFixture()
            let occurrence = fixture.makeOccurrence(
                title: "合成任务", scheduledAt: fixture.now, status: .pending)
            try fixture.context.save()
            let result = try TaskCompletionService(context: fixture.context).complete(
                occurrence, at: fixture.now, source: .childManual)
            let arguments =
                (isolated ? [UITestLaunchConfiguration.enableArgument] : [])
                + (failure ? [UITestTodayViewModelFactory.qualificationFailureArgument] : [])
            let model = UITestTodayViewModelFactory.make(
                context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
                dateProvider: FixedDateProvider(value: fixture.now), arguments: arguments)
            model.receive(completion: result)
            model.load()
            #expect(model.celebrationVerificationFailed == (isolated && failure))
            #expect((model.celebrationModel.event == nil) == (isolated && failure))
            #expect(occurrence.status == .completed && !fixture.context.hasChanges)
            #expect(model.rewardState == .loaded(try RewardLedgerService(context: fixture.context).balance()))
        }
    }
#endif
