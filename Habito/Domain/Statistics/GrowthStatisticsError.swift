import Foundation

/// 统计不静默吞掉重复或矛盾事实，否则可信的分母会被悄悄改变。
nonisolated enum GrowthStatisticsError: Error, Equatable {
    case invalidWindowEnd(LocalDate)
    case duplicateOccurrence(UUID)
    case duplicateTemplateDate(UUID, LocalDate)
    case invalidFact(UUID)
}
