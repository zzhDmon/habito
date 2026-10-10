import Foundation

/// 摄像头状态与任务计时相互独立；相机失败不能阻止孩子完成任务。
nonisolated enum FrontCameraState: Equatable, Sendable {
    case idle, requestingPermission, running, denied, restricted, unavailable, failed, interrupted

    var messageKey: String {
        switch self {
        case .idle: "taskCamera.idle"
        case .requestingPermission: "taskCamera.requesting"
        case .running: "taskCamera.live"
        case .denied: "taskCamera.denied"
        case .restricted: "taskCamera.restricted"
        case .unavailable: "taskCamera.unavailable"
        case .failed: "taskCamera.failed"
        case .interrupted: "taskCamera.interrupted"
        }
    }
}
