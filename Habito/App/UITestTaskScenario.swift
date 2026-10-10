#if DEBUG
    import Foundation

    /// 显式 UI 合成场景，不是产品默认配置；仅在专用 Debug 测试启动分支解析。
    enum UITestTaskScenario: String, CaseIterable {
        case legacy
        case rewardSelfConfirm = "reward-self-confirm"
        case rewardAfterReminder = "reward-after-reminder"
        case zeroRewardSelfConfirm = "zero-reward-self-confirm"
        case corruptRewardLedger = "corrupt-reward-ledger"
        case dailyIncome = "daily-income"
        case petCare = "pet-care"
        case parentApproval = "parent-approval"
        case zeroRewardParentApproval = "zero-reward-parent-approval"
        case returnedSubmission = "returned-submission"
        case targetReachedSelfConfirm = "target-reached-self-confirm"
        case targetReachedParentApproval = "target-reached-parent-approval"
        case taskSwitch = "task-switch"

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
            case .legacy, .rewardSelfConfirm, .rewardAfterReminder, .zeroRewardSelfConfirm, .corruptRewardLedger,
                .dailyIncome, .petCare, .targetReachedSelfConfirm, .taskSwitch:
                .selfConfirm
            case .parentApproval, .zeroRewardParentApproval, .returnedSubmission, .targetReachedParentApproval:
                .parentApproval
            }
        }

        /// 零奖励审核同样完整跑业务闭环，不靠旧任务自行确认替代家长审核验收。
        var hasSyntheticReward: Bool {
            self != .legacy && self != .zeroRewardParentApproval && self != .zeroRewardSelfConfirm
                && self != .corruptRewardLedger && self != .taskSwitch
        }

        /// 合成场景用固定相对时刻区分普通与自主反馈，不靠等待计时或修改系统时间。
        var reminderOffset: TimeInterval {
            switch self {
            case .legacy, .rewardAfterReminder: -60
            default: 60
            }
        }
    }
#endif
