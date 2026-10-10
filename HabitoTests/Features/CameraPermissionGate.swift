import Foundation
import Testing
@testable import Habito

/// 手动控制权限返回顺序，复现授权弹窗期间暂停或离开的竞态。
actor CameraPermissionGate {
    private var permissionContinuation: CheckedContinuation<FrontCameraState?, Never>?
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false

    func request() async -> FrontCameraState? {
        await withCheckedContinuation { continuation in
            permissionContinuation = continuation
            hasEntered = true
            entryContinuation?.resume()
            entryContinuation = nil
        }
    }
    func waitUntilRequested() async {
        if hasEntered { return }
        await withCheckedContinuation { entryContinuation = $0 }
    }
    func resolve(_ failure: FrontCameraState? = nil) {
        permissionContinuation?.resume(returning: failure)
        permissionContinuation = nil
    }
}
