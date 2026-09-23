import Foundation
import Testing
@testable import Habito

@Suite("家长 PIN Keychain 凭据", .serialized)
@MainActor
struct KeychainParentPINCredentialStoreTests {
    @Test("隔离账户支持保存验证更新删除且不保存可直接匹配的明文")
    func roundTripAndReplace() throws {
        let uniqueID = UUID().uuidString
        let store = KeychainParentPINCredentialStore(
            service: "com.zhangzehua.Habito.tests.\(uniqueID)",
            account: "parent-pin.\(uniqueID)"
        )
        try store.removeCredential()
        #expect(try !store.containsCredential())

        try store.store(ParentPIN("1357"))
        #expect(try store.containsCredential())
        #expect(try store.verify(ParentPIN("1357")))
        #expect(try !store.verify(ParentPIN("2468")))

        try store.store(ParentPIN("2468"))
        #expect(try !store.verify(ParentPIN("1357")))
        #expect(try store.verify(ParentPIN("2468")))

        try store.removeCredential()
        #expect(try !store.containsCredential())
    }
}
