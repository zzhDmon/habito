import Foundation

/// 规则展开后得到的单日任务候选。
///
/// `date` 用于后续生成稳定的本地日期键，`scheduledAt` 则是结合业务日历与时区后
/// 得到的绝对时刻。此类型不包含持久化身份，M1-005 才会负责实例的幂等写入。
nonisolated struct ScheduledTaskCandidate: Equatable, Sendable {
    let date: LocalDate
    let scheduledAt: Date
}
