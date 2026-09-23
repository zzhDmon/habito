import Foundation
@testable import Habito

/// 持久化往返测试使用的完整八模型对象图。
struct PersistenceFixture {
    let templateID: UUID
    let template: TaskTemplate
    let rule: ReminderRule
    let occurrence: TaskOccurrence
    let completion: CompletionRecord
    let session: TimerSession
    let link: NotificationLink
    let dayOverride: DayOverride
    let settings: AppSettings
}
