import SwiftUI

/// 展示计时的集中格式化入口，不自行读取设备时钟或改变累计秒数。
enum TaskSessionDurationText {
    static func clock(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func spoken(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String.localizedStringWithFormat(
            String(localized: "taskSession.elapsedSpokenFormat"),
            seconds / 60,
            seconds % 60
        )
    }
}
