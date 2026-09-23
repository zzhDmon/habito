import Testing
@testable import Habito

@Suite("家长 PIN 格式")
struct ParentPINTests {
    @Test("只接受四位 ASCII 数字")
    func acceptsOnlyFourASCIIDigits() throws {
        _ = try ParentPIN("1357")

        #expect(throws: ParentPINError.invalidFormat) { try ParentPIN("123") }
        #expect(throws: ParentPINError.invalidFormat) { try ParentPIN("12345") }
        #expect(throws: ParentPINError.invalidFormat) { try ParentPIN("12a4") }
        #expect(throws: ParentPINError.invalidFormat) { try ParentPIN("１２３４") }
    }
}
