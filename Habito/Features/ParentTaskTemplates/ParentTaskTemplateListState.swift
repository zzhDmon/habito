/// 家长模板列表的完整页面状态。
enum ParentTaskTemplateListState: Equatable {
    case loading
    case loaded([ParentTaskTemplateListItem])
    case failed
}
