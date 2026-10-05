/// V1 最小闭环只支持自行确认与家长验收，照片不提前写入可选入口。
nonisolated enum TaskVerificationType: String, CaseIterable, Sendable {
    case selfConfirm
    case parentApproval
}
