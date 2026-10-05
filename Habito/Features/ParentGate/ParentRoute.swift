/// 家长区的类型安全导航目标。
enum ParentRoute: Hashable {
    case review
    case today
    case calendar
    case notifications
    case template(ParentTaskTemplateRoute)
}
