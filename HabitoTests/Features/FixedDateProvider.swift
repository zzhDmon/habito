import Foundation
@testable import Habito

/// 页面模型测试使用的固定墙上时钟。
nonisolated struct FixedDateProvider: DateProviding {
    let value: Date

    func now() -> Date {
        value
    }
}
