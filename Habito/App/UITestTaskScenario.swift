#if DEBUG
    import Foundation

    /// 显式 UI 合成场景，不是产品默认配置；仅在专用 Debug 测试启动分支解析。
    enum UITestTaskScenario: String, CaseIterable {
        case legacy
        case rewardSelfConfirm = "reward-self-confirm"
        case parentApproval = "parent-approval"
        case returnedSubmission = "returned-submission"

        static let argument = "--habito-ui-task-scenario"

        /// 坏参数明确失败，绝不能为回退夹具而切回正式数据库。
        static func parse(arguments: [String]) throws -> Self {
            guard let index = arguments.firstIndex(of: argument) else { return .legacy }
            guard arguments.indices.contains(index + 1), let scenario = Self(rawValue: arguments[index + 1]) else {
                throw CocoaError(.coderInvalidValue)
            }
            return scenario
        }

        var verificationType: TaskVerificationType {
            switch self {
            case .legacy, .rewardSelfConfirm: .selfConfirm
            case .parentApproval, .returnedSubmission: .parentApproval
            }
        }
    }
#endif
