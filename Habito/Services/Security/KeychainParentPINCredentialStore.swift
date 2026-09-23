import CryptoKit
import Foundation
import Security

/// 使用 Keychain 保存版本化盐值与摘要的家长 PIN 凭据。
///
/// 四位 PIN 的搜索空间很小，因此本实现不把摘要当作独立的强密码保护；安全边界仍依赖
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 的本机 Keychain。随机盐用于避免相同 PIN
/// 产生相同持久化内容，恒定时间比较降低验证时序泄露。
struct KeychainParentPINCredentialStore: ParentPINCredentialStoring {
    private struct StoredCredential: Codable {
        let version = 1
        let salt: Data
        let digest: Data
    }

    private let service: String
    private let account: String

    init(
        service: String = "com.zhangzehua.Habito.parent-pin",
        account: String = AppSettings.parentPINKeychainAccount
    ) {
        self.service = service
        self.account = account
    }

    func containsCredential() throws -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw KeychainParentPINError.unexpectedStatus(status)
    }

    func store(_ pin: ParentPIN) throws {
        let salt = try randomSalt()
        let credential = StoredCredential(salt: salt, digest: digest(pin: pin, salt: salt))
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainParentPINError.unexpectedStatus(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainParentPINError.unexpectedStatus(addStatus)
        }
    }

    func verify(_ pin: ParentPIN) throws -> Bool {
        guard let data = try credentialData() else { return false }
        let credential: StoredCredential
        do {
            credential = try JSONDecoder().decode(StoredCredential.self, from: data)
        } catch {
            throw KeychainParentPINError.invalidCredential
        }
        guard credential.version == 1 else { throw KeychainParentPINError.invalidCredential }
        return constantTimeEqual(credential.digest, digest(pin: pin, salt: credential.salt))
    }

    func removeCredential() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainParentPINError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func credentialData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainParentPINError.unexpectedStatus(status)
        }
        return data
    }

    private func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainParentPINError.unexpectedStatus(status)
        }
        return Data(bytes)
    }

    private func digest(pin: ParentPIN, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + pin.utf8Data))
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
