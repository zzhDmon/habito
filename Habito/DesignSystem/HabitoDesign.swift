import SwiftUI

/// Habito 全局视觉令牌。
///
/// 页面只引用语义名称，不直接散落数值。后续调整儿童视觉风格时，可以在这里统一修改，
/// 同时保留 Dynamic Type 和不同 iPad 尺寸下的系统自适应能力。
enum HabitoDesign {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum CornerRadius {
        static let badge: CGFloat = 12
        static let card: CGFloat = 24
    }

    enum Layout {
        static let minimumTapSize: CGFloat = 44
        static let maximumContentWidth: CGFloat = 1_200
        static let columnMinimumWidth: CGFloat = 320
    }

    enum Palette {
        static let accent = Color.indigo
        static let task = Color.blue
        static let success = Color.green
        static let attention = Color.orange
    }

    enum Symbol {
        static let pending = "clock"
        static let completed = "checkmark.circle.fill"
        static let parent = "person.badge.key.fill"
    }

    /// 完成仪式的视觉节奏，不参与奖励计算或撤销计时；减少动态效果时不使用位移动画。
    enum Feedback {
        static let symbolSize: CGFloat = 64
        static let symbolPadding: CGFloat = 20
        // 纯数值不可变且 Sendable，供无 actor 状态的展示策略测试读取；颜色/动画仍留在 UI 层。
        nonisolated static let initialScale = 0.92
        nonisolated static let initialOpacity = 0.7
        static let reveal = Animation.spring(duration: 0.45, bounce: 0.2)
        static let cardTintOpacity = 0.12
        static let badgeTintOpacity = 0.16
        static let completed = Color.green
        static let autonomous = Color.indigo
        static let xp = Color.indigo
        static let coins = Color.orange
    }
}
