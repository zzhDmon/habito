import Foundation

/// 家长模板区的类型安全导航目标；编辑内容由 M3-003 接入。
enum ParentTaskTemplateRoute: Hashable {
    case create
    case detail(UUID)
}
