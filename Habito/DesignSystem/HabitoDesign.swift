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
}
