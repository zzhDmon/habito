/// 家长区的类型安全导航目标。
enum ParentRoute: Hashable {
    case today
    case calendar
    case notifications
    case template(ParentTaskTemplateRoute)
}
