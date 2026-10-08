import SwiftData

/// 已观察等级只用于去重升级反馈；当前等级始终由有效XP派生，不能用该字段当余额。
///
/// 首次建立当前基线不播放历史升级；保存观察点成功后才允许展示一次反馈。
@Model
final class PetGrowthCheckpoint {
    @Attribute(.unique) private(set) var petKey: String
    private(set) var observedLevel: Int

    init(petKey: String, observedLevel: Int) {
        self.petKey = petKey
        self.observedLevel = observedLevel
    }

    /// 仅供同一主actor反馈事务使用；失败时调用方恢复旧值，兼容17的对象缓存。
    func observe(level: Int) { observedLevel = level }
}
