import Foundation
import OSLog
import SwiftData

/// 把系统通知标识解析为当前持久化状态允许进入的页面。
@MainActor
struct NotificationNavigationService {
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "NotificationNavigation")

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
        do {
            guard let occurrence = try context.fetch(descriptor).first, let status = occurrence.status else {
                return .home
            }
            // 系统卡片可晚于孩子提交被点击，不能以原 pending 值重新开放执行入口。
            if try TaskSubmissionHistory(context: context).latest(for: occurrence)?.reviewState == .waiting {
                return .home
            }
            switch status {
            case .pending, .inProgress:
                return .task(occurrenceID)
            case .completed, .skipped, .cancelled:
                return .home
            }
        } catch {
            // 点击入口不能抛出给系统 delegate；保留错误类型诊断，安全回首页且不记录孩子数据。
            logger.error("通知目标事实校验失败：\(String(describing: type(of: error)), privacy: .public)")
            return .home
        }
    }
}
