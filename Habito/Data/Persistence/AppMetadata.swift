import Foundation
import SwiftData

/// 应用级持久化元数据。
///
/// M0 使用这个最小模型验证 SwiftData 容器和测试配置。业务任务模型会在 M1 独立加入，
/// 不应把任务字段临时堆进这个类型。
@Model
final class AppMetadata {
    var createdAt: Date

    init(createdAt: Date = .now) {
        self.createdAt = createdAt
    }
}
