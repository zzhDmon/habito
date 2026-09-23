import Foundation

/// 正式应用使用的系统墙上时钟。
nonisolated struct SystemDateProvider: DateProviding {
    func now() -> Date {
        .now
    }
}
