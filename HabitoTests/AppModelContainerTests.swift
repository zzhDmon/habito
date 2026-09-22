import Testing
@testable import Habito

@Suite("SwiftData 容器")
struct AppModelContainerTests {
    @Test("可以创建独立的内存容器")
    func createsInMemoryContainer() throws {
        _ = try AppModelContainer.make(inMemory: true)
    }
}
