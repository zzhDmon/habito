import Observation
import OSLog

/// 家长名字设置的主actor草稿，界面只绑定字段和转发意图，不直接访问SwiftData。
///
/// `@Observable`实例由组合根持有；构造不读取资料，只有PIN后页面明确触发load。
@MainActor
@Observable
final class FamilyProfileEditorViewModel {
    var childNickname = "" {
        didSet { clearFeedbackIfEdited(oldValue: oldValue, newValue: childNickname) }
    }
    var petName = "" {
        didSet { clearFeedbackIfEdited(oldValue: oldValue, newValue: petName) }
    }
    private(set) var loadState: FamilyProfileEditorLoadState = .idle
    private(set) var feedback: FamilyProfileEditorFeedback?
    private(set) var hasStoredNames = false
    private(set) var isSaving = false

    private let loadNames: () throws -> FamilyProfileNames?
    private let saveNames: (FamilyProfileNames) throws -> Bool
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "FamilyProfileEditor")

    /// 注入窄同步边界；不在初始化时预读取家长资料。
    ///
    /// - Parameters:
    ///   - loadNames: 显式只读查询，未设置返回nil，坏存储/系统失败须抛出。
    ///   - saveNames: 配对原子保存；返回是否变更，同值幂等也属于保存成功。
    init(
        loadNames: @escaping () throws -> FamilyProfileNames?,
        saveNames: @escaping (FamilyProfileNames) throws -> Bool
    ) {
        self.loadNames = loadNames
        self.saveNames = saveNames
    }

    /// 首次显式载入，重复页面task不覆盖家长正在输入的草稿。
    func load() {
        guard loadState == .idle else { return }
        performLoad()
    }

    /// 只有失败态允许明确重试；正常编辑中的重试不能重读抹掉草稿。
    func retryLoad() {
        guard loadState == .failed else { return }
        performLoad()
    }

    /// 校验并保存两名字，失败保留草稿，成功回显去两端空白后的真实配置。
    ///
    /// - Returns: 名字是否可确认为已保存；未载入、失败态、重入或任何错误返回false。
    /// - Note: 相同名字的事务幂等结果也返回true，没有额外资料/奖励写入。
    @discardableResult
    func save() -> Bool {
        guard loadState == .ready, !isSaving else { return false }
        feedback = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let names = try FamilyProfileNames(childNickname: childNickname, petName: petName)
            _ = try saveNames(names)
            childNickname = names.childNickname
            petName = names.petName
            hasStoredNames = true
            feedback = .saved
            return true
        } catch let error as FamilyProfileNameError {
            feedback = .validation(error)
            return false
        } catch {
            logger.error("名字保存失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = .storageFailure
            return false
        }
    }

    /// 家长区关闭后撤下内存名字和反馈；再次进入须经门禁后显式读取。
    func reset() {
        guard !isSaving else { return }
        clearDraft()
        loadState = .idle
    }

    private func performLoad() {
        feedback = nil
        do {
            let names = try loadNames()
            childNickname = names?.childNickname ?? ""
            petName = names?.petName ?? ""
            hasStoredNames = names != nil
            loadState = .ready
        } catch {
            clearDraft()
            loadState = .failed
            logger.error("名字载入失败：\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func clearDraft() {
        childNickname = ""
        petName = ""
        feedback = nil
        hasStoredNames = false
    }

    /// 编辑后旧成功/错误不再描述当前草稿；相同字节的程序回写不撤下反馈。
    private func clearFeedbackIfEdited(oldValue: String, newValue: String) {
        guard !oldValue.utf8.elementsEqual(newValue.utf8) else { return }
        feedback = nil
    }
}
