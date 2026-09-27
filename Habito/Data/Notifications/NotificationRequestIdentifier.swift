import Foundation

/// 可由系统请求稳定反查任务实例和通知用途的标识。
///
/// 主提醒与稍后提醒都使用固定槽位；同一实例再次排程会替换旧请求，避免稍后提醒累积。
nonisolated struct NotificationRequestIdentifier: Equatable, Hashable, Sendable {
    static let namespace = "habito.occurrence"

    let occurrenceID: UUID
    let kind: NotificationKind

    var rawValue: String {
        "\(Self.namespace).\(occurrenceID.uuidString.lowercased()).\(kind.rawValue)"
    }

    init(occurrenceID: UUID, kind: NotificationKind) {
        self.occurrenceID = occurrenceID
        self.kind = kind
    }

    /// 解析系统回传标识；非 Habito、未知用途或格式不完整时返回 `nil`。
    init?(rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard
            components.count == 4,
            components[0] == "habito",
            components[1] == "occurrence",
            let occurrenceID = UUID(uuidString: String(components[2])),
            let kind = NotificationKind(rawValue: String(components[3]))
        else {
            return nil
        }
        self.occurrenceID = occurrenceID
        self.kind = kind
    }
}
