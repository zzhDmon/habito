import Foundation
import SwiftData

/// 在应用组合根保存任务执行页所需依赖，并为每个稳定实例 ID 创建独立页面模型。
@MainActor
struct TaskSessionViewModelFactory {
    private let context: ModelContext
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let dateProvider: any DateProviding

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding
    ) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.dateProvider = dateProvider
    }

    func makeModel(for occurrenceID: UUID) -> TaskSessionViewModel {
        TaskSessionViewModel(
            occurrenceID: occurrenceID,
            context: context,
            calendar: calendar,
            timeZone: timeZone,
            dateProvider: dateProvider
        )
    }
}
