import Observation
import OSLog

/// 组合根持有的主actor只读状态；儿童界面只发起读取，编辑始终由现有PIN后服务负责。
@MainActor
@Observable
final class PetProfileViewModel {
    private(set) var state: PetProfileViewState = .loading
    private let loadNames: () throws -> FamilyProfileNames?
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "PetProfile")

    /// 构造不读库；窄同步边界便于测试读取失败，避免将可写ModelContext交给View。
    init(loadNames: @escaping () throws -> FamilyProfileNames?) {
        self.loadNames = loadNames
    }

    /// 进入、前台和家长关闭时刷新；错误撤下旧名字，不能让未保存草稿看起来已生效。
    func load() {
        state = .loading
        do {
            state = try loadNames().map(PetProfileViewState.loaded) ?? .notConfigured
        } catch {
            logger.error("小狗资料读取失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
    }
}
