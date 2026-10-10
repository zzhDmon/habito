import Foundation

/// 隔离系统摄像头与页面状态，测试使用替身而不访问真实镜头或系统权限。
nonisolated protocol FrontCameraCapturing: Sendable {
    /// 应用最新启停意图；旧世代的授权结果不得重新打开镜头。
    /// - Parameters:
    ///   - enabled: 仅在当前任务运行且页面位于前台时为 true。
    ///   - revision: 同一页面服务内严格递增的意图世代，用于处理授权期间的 actor 重入。
    /// - Returns: 相机状态；关闭始终返回 idle，错误只影响预览。
    func setEnabled(_ enabled: Bool, revision: UInt64) async -> FrontCameraState
}
