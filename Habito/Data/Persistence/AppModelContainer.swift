import Foundation
import SwiftData

/// 统一创建 Habito 的 SwiftData 容器。
///
/// 正式应用使用磁盘存储；单元测试和 Preview 应传入 `inMemory: true`，
/// 以免测试数据写入用户的真实数据库。
enum AppModelContainer {
    /// V0 的完整持久化模型清单。新增或迁移模型时只在这里维护组合根。
    static let schema = Schema([
        TaskTemplate.self,
        ReminderRule.self,
        TaskOccurrence.self,
        CompletionRecord.self,
        TimerSession.self,
        DayOverride.self,
        NotificationLink.self,
        AppSettings.self,
    ])

    /// 创建包含当前应用模型的 SwiftData 容器。
    ///
    /// - Parameter inMemory: `true` 表示只在内存中保存，适用于测试和 Preview。
    /// - Returns: 配置完成的模型容器。
    /// - Throws: SwiftData 无法创建存储或加载模型时抛出错误，由调用方决定如何呈现或终止。
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        return try make(configuration: configuration)
    }

    /// 使用明确磁盘位置创建容器，供持久化重开测试与未来迁移工具使用。
    ///
    /// - Parameter storeURL: SQLite 主存储文件位置；SwiftData 会在同目录管理辅助文件。
    /// - Returns: 使用 V0 完整模型的磁盘容器。
    /// - Throws: 目录不可写、模型不兼容或存储无法打开时抛出 SwiftData 错误。
    static func make(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        return try make(configuration: configuration)
    }

    private static func make(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
