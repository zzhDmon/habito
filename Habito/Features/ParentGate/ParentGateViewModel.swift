import Observation
import OSLog
import SwiftData

/// 协调家长门禁状态、Keychain 凭据与 SwiftData 非敏感引用。
@MainActor
@Observable
final class ParentGateViewModel {
    enum State: Equatable {
        case loading
        case setup
        case verify
        case unlocked
        case failed
    }

    enum Feedback: Equatable {
        case invalidFormat
        case confirmationMismatch
        case incorrectPIN
        case storageFailure
    }

    private(set) var state: State = .loading
    private(set) var feedback: Feedback?

    private let context: ModelContext
    private let credentialStore: any ParentPINCredentialStoring
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ParentGate")

    init(context: ModelContext, credentialStore: any ParentPINCredentialStoring) {
        self.context = context
        self.credentialStore = credentialStore
    }

    /// 每次展示门禁前重新读取实际凭据，并修复 SwiftData 中的非敏感引用。
    func prepareForPresentation() {
        state = .loading
        feedback = nil
        do {
            let settings = try fetchOrCreateSettings()
            let hasCredential = try credentialStore.containsCredential()
            if hasCredential != settings.hasParentPIN {
                hasCredential ? settings.markParentPINStored() : settings.clearParentPINReference()
                try context.save()
            }
            state = hasCredential ? .verify : .setup
        } catch {
            handle(error)
        }
    }

    /// 校验两次输入并原子地先写 Keychain、再记录 SwiftData 引用。
    func createPIN(_ rawPIN: String, confirmation: String) {
        feedback = nil
        do {
            let pin = try ParentPIN(rawPIN)
            let repeatedPIN = try ParentPIN(confirmation)
            guard pin == repeatedPIN else {
                feedback = .confirmationMismatch
                return
            }
            try credentialStore.store(pin)
            let settings = try fetchOrCreateSettings()
            settings.markParentPINStored()
            try context.save()
            state = .unlocked
            // 只记录状态事件，不记录输入、凭据或家庭数据；帮助区分保存与界面切换故障。
            logger.info("家长凭据创建成功，本次门禁已解锁")
        } catch ParentPINError.invalidFormat {
            feedback = .invalidFormat
        } catch {
            handle(error)
        }
    }

    /// 验证成功后仅改变当前页面状态，不把 PIN 或解锁状态持久化。
    func verifyPIN(_ rawPIN: String) {
        feedback = nil
        do {
            let pin = try ParentPIN(rawPIN)
            if try credentialStore.verify(pin) {
                state = .unlocked
                logger.info("本次家长凭据验证成功，门禁已解锁")
            } else {
                feedback = .incorrectPIN
            }
        } catch ParentPINError.invalidFormat {
            feedback = .invalidFormat
        } catch {
            handle(error)
        }
    }

    /// 本机重置只删除门禁凭据，不删除任务、完成记录或其他家庭数据。
    func resetPIN() {
        feedback = nil
        do {
            try credentialStore.removeCredential()
            let settings = try fetchOrCreateSettings()
            settings.clearParentPINReference()
            try context.save()
            state = .setup
        } catch {
            handle(error)
        }
    }

    private func fetchOrCreateSettings() throws -> AppSettings {
        let key = AppSettings.defaultKey
        let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.singletonKey == key })
        if let settings = try context.fetch(descriptor).first { return settings }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    private func handle(_ error: Error) {
        logger.error("家长门禁存储操作失败：\(String(describing: type(of: error)), privacy: .public)")
        feedback = .storageFailure
        state = .failed
    }
}
