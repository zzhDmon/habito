import Foundation

/// 集中维护自动化测试和辅助功能检查使用的稳定控件标识。
///
/// 标识只描述控件语义，不依赖可见中文文案或视图层级，因此文案调整和横竖屏布局变化
/// 不会让 UI 测试失效。动态任务标识拼接持久化实例 ID，避免同名任务产生歧义。
nonisolated enum HabitoAccessibilityID {
    static let todayScreen = "kid.today.screen"
    static let sessionScreen = "kid.session.screen"
    static let elapsedTime = "kid.session.elapsed"
    static let startButton = "kid.session.start"
    static let pauseButton = "kid.session.pause"
    static let resumeButton = "kid.session.resume"
    static let completeButton = "kid.session.complete"
    static let undoButton = "kid.session.undo"

    static func task(_ id: UUID) -> String {
        "kid.today.task.\(id.uuidString.lowercased())"
    }
}
