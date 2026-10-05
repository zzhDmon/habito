import Foundation
import Testing
@testable import Habito

@Suite("UI 自动化测试时钟")
struct UITestDateProviderTests {
    @Test("真实午夜不改变场景日期，重启仍连续计时", arguments: [0.0, 120.0, 1_200.0])
    func midnightAndRelaunchPreserveScenario(elapsed: TimeInterval) throws {
        let reference = try Date("2026-10-04T15:50:00Z", strategy: .iso8601)
        let base = try Date("2026-09-27T02:00:00Z", strategy: .iso8601)
        let sample = reference.addingTimeInterval(elapsed)
        let first = UITestDateProvider(
            referenceSystemDate: reference, referenceTestDate: base,
            systemDateProvider: FixedDateProvider(value: sample))
        let reopened = UITestDateProvider(
            referenceSystemDate: reference, referenceTestDate: base,
            systemDateProvider: FixedDateProvider(value: sample.addingTimeInterval(30)))
        #expect(first.now() == base.addingTimeInterval(elapsed))
        #expect(reopened.now().timeIntervalSince(first.now()) == 30)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        #expect(
            try LocalDate(date: reopened.now(), calendar: Calendar(identifier: .gregorian), timeZone: timeZone).dateKey
                == "2026-09-27")
    }

    @Test("显式错误基准拒绝而非静默使用系统时钟", arguments: ["", "NaN", "inf", "1e999"])
    func invalidReferenceIsRejected(_ reference: String) {
        #expect(throws: CocoaError.self) {
            try configuration().makeDateProvider(environment: [
                UITestLaunchConfiguration.systemReferenceEnvironmentKey: reference
            ])
        }
    }

    @Test("有效测试环境使用映射时钟，没有环境的手工探针保持系统时钟")
    func clockIsOptInForTesting() throws {
        let configuration = configuration()
        #expect(try configuration.makeDateProvider(environment: [:]) is SystemDateProvider)
        #expect(
            try configuration.makeDateProvider(environment: [
                UITestLaunchConfiguration.systemReferenceEnvironmentKey: "1791129000"
            ])
                is UITestDateProvider)
    }

    private func configuration() -> UITestLaunchConfiguration {
        UITestLaunchConfiguration(
            shouldReset: false, shouldSeedSampleData: true, shouldSeedTemplateOnly: false,
            notificationRequestIdentifier: nil, shouldPrepareNotificationResponse: false,
            shouldDenyNotifications: false, shouldFailNotificationScheduling: false)
    }
}
