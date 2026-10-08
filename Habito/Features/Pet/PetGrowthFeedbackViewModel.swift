import Observation
import OSLog

/// 已领取升级的短暂展示状态；返回/刷新不重复领取，错误和纠错会撤下已失效升级。
@MainActor
@Observable
final class PetGrowthFeedbackViewModel {
    private(set) var event: PetGrowthObservation?
    private(set) var failed = false
    private let observe: () throws -> PetGrowthObservation?
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "PetGrowthFeedback")

    init(observe: @escaping () throws -> PetGrowthObservation?) { self.observe = observe }

    func refresh() {
        do {
            guard let result = try observe() else { event = nil; failed = false; return }
            failed = false
            if result.didLevelUp {
                event = PetGrowthObservation(
                    previousLevel: event?.previousLevel ?? result.previousLevel,
                    currentLevel: result.currentLevel)
            } else if let event, result.currentLevel < event.currentLevel {
                self.event = nil
            }
        } catch {
            event = nil
            failed = true
            logger.error("成长反馈核对失败：\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    func dismiss() { event = nil }
}
