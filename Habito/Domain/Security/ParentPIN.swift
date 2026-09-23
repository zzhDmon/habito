import Foundation

/// 经过格式校验的四位家长 PIN。
///
/// 该值只在一次创建或验证操作期间存在于内存，不可编码，也不会写入 SwiftData、日志或错误信息。
nonisolated struct ParentPIN: Equatable, Sendable {
    private let value: String

    /// 创建四位数字 PIN。
    ///
    /// - Parameter value: 用户输入；只接受四个 ASCII 数字，避免不同数字字符产生视觉混淆。
    /// - Throws: 输入不是四位 ASCII 数字时抛出 `ParentPINError.invalidFormat`。
    init(_ value: String) throws {
        guard value.utf8.count == 4, value.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw ParentPINError.invalidFormat
        }
        self.value = value
    }

    /// 仅供凭据派生服务读取的短生命周期字节；调用方不得持久化或记录。
    var utf8Data: Data {
        Data(value.utf8)
    }
}
