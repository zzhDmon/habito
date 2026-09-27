import Foundation
import SwiftData

/// 把系统通知标识解析为当前持久化状态允许进入的页面。
@MainActor
struct NotificationNavigationService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 非 Habito 通知不干扰当前页面；Habito 目标失效时统一安全回首页。
    func destination(for requestIdentifier: String) -> NotificationNavigationDestination {
        guard let identifier = NotificationRequestIdentifier(rawValue: requestIdentifier) else {
            return .ignored
        }
        let occurrenceID = identifier.occurrenceID
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.id == occurrenceID }
        )
        guard
            let occurrence = try? context.fetch(descriptor).first,
            let status = occurrence.status
        else {
            return .home
        }
        switch status {
        case .pending, .inProgress:
            return .task(occurrenceID)
        case .completed, .skipped:
            return .home
        }
    }
}
