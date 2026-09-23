@testable import Habito

/// 门禁单元测试使用的内存凭据替身，避免测试依赖或污染系统 Keychain。
@MainActor
final class InMemoryParentPINCredentialStore: ParentPINCredentialStoring {
    private(set) var storedPIN: ParentPIN?

    init(storedPIN: ParentPIN? = nil) {
        self.storedPIN = storedPIN
    }

    func containsCredential() throws -> Bool {
        storedPIN != nil
    }

    func store(_ pin: ParentPIN) throws {
        storedPIN = pin
    }

    func verify(_ pin: ParentPIN) throws -> Bool {
        storedPIN == pin
    }

    func removeCredential() throws {
        storedPIN = nil
    }
}
