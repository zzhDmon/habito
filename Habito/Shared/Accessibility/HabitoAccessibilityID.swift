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
    static let parentEntry = "parent.gate.entry"
    static let parentPINField = "parent.gate.pin"
    static let parentPINConfirmationField = "parent.gate.pin-confirmation"
    static let parentCreateButton = "parent.gate.create"
    static let parentUnlockButton = "parent.gate.unlock"
    static let parentResetButton = "parent.gate.reset"
    static let parentUnlocked = "parent.gate.unlocked"
    static let parentTemplateCreate = "parent.templates.create"
    static let parentTodayOpen = "parent.today.open"
    static let parentTodayScreen = "parent.today.screen"
    static let parentTodayTimeSave = "parent.today.time.save"
    static let parentCalendarOpen = "parent.calendar.open"
    static let parentCalendarScreen = "parent.calendar.screen"
    static let parentCalendarSchoolDay = "parent.calendar.school-day"
    static let parentCalendarHoliday = "parent.calendar.holiday"
    static let parentCalendarRemoveOverride = "parent.calendar.remove-override"
    static let parentCalendarConfirm = "parent.calendar.confirm"
    static let parentNotificationDiagnosticsOpen = "parent.notifications.open"
    static let parentNotificationDiagnostics = "parent.notifications.screen"
    static let taskEditorScreen = "parent.templates.editor"
    static let taskEditorTitle = "parent.templates.editor.title"
    static let taskEditorDuration = "parent.templates.editor.duration"
    static let taskEditorSave = "parent.templates.editor.save"
    static let taskLifecycleDisable = "parent.templates.lifecycle.disable"
    static let taskLifecycleEnable = "parent.templates.lifecycle.enable"
    static let taskLifecycleArchive = "parent.templates.lifecycle.archive"
    static let taskLifecycleConfirm = "parent.templates.lifecycle.confirm"
    static let taskLifecycleCancel = "parent.templates.lifecycle.cancel"

    static func task(_ id: UUID) -> String {
        "kid.today.task.\(id.uuidString.lowercased())"
    }

    static func parentTemplate(_ id: UUID) -> String {
        "parent.templates.item.\(id.uuidString.lowercased())"
    }

    static func parentTodayTask(_ id: UUID) -> String {
        "parent.today.task.\(id.uuidString.lowercased())"
    }

    static func parentTodayActions(_ id: UUID) -> String {
        "parent.today.actions.\(id.uuidString.lowercased())"
    }
}
