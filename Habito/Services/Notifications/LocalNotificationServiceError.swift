import Foundation

/// 本地通知服务能够在应用内识别的输入错误。
enum LocalNotificationServiceError: Error, Equatable {
    /// 非重复时间通知要求延迟至少为一秒。
    case invalidDelay
}
