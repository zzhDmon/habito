import Testing
@testable import Habito

@Suite("SwiftData 容器")
struct AppModelContainerTests {
    @Test("内存容器包含十一业务模型和两份真实名字资料")
    func createsInMemoryContainerWithCompleteSchema() throws {
        _ = try AppModelContainer.make(inMemory: true)

        #expect(AppModelContainer.schema.entities.count == 13)
        #expect(HabitoSchemaV3.models.count == 10)
        #expect(HabitoSchemaV4.models.count == 11 && HabitoSchemaV5.models.count == 11)
        #expect(HabitoSchemaV6.models.count == 11)
        #expect(HabitoSchemaV7.models.count == 13)
    }

    @Test("家长 PIN 只记录固定 Keychain 账户引用")
    func parentPINUsesOnlyFixedKeychainReference() {
        let settings = AppSettings(hasParentPIN: true)

        #expect(settings.hasParentPIN)
        #expect(settings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)

        settings.clearParentPINReference()
        #expect(!settings.hasParentPIN)

        settings.markParentPINStored()
        #expect(settings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)
    }
}
