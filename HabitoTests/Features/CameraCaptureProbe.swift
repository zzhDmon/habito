import Foundation
@testable import Habito

/// 同步硬件替身：锁只保护测试调用记录，生产会话由 actor 隔离。
nonisolated final class CameraCaptureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    let result: FrontCameraState
    init(result: FrontCameraState = .running) { self.result = result }
    func capture(_ enabled: Bool) -> FrontCameraState {
        lock.withLock { values.append(enabled) }
        return enabled ? result : .idle
    }
    var requests: [Bool] { lock.withLock { values } }
}
