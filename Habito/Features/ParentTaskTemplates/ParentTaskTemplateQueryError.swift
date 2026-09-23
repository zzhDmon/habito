import Foundation

/// 模板列表无法安全解释本地数据时返回的明确错误。
enum ParentTaskTemplateQueryError: Error, Equatable {
    case invalidTemplate(UUID)
    case cannotAdvanceDate(LocalDate)
}
