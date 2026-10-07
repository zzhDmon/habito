/// 家长区的类型安全导航目标。
enum ParentRoute: Hashable {
    case familyProfile
    case review
    case today
    case statistics
    case calendar
    case notifications
    case template(ParentTaskTemplateRoute)
}
