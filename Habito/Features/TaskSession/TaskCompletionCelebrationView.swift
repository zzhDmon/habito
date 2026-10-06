import SwiftUI

/// 完成后的主视觉，文字肯定与徽标同时表达结果，不能仅靠颜色或动态效果区别自主。
struct TaskCompletionCelebrationView: View {
    let isAutonomous: Bool
    let hasReward: Bool
    // ScaledMetric 随当前页面系统字号更新；只缩放装饰符号，不限制正文行数或操作区高度。
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = HabitoDesign.Feedback.symbolSize

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Image(systemName: isAutonomous ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.system(size: symbolSize))
                .foregroundStyle(tint)
                .padding(HabitoDesign.Feedback.symbolPadding)
                .background(tint.opacity(HabitoDesign.Feedback.badgeTintOpacity), in: Circle())
                .accessibilityHidden(true)
            Text("taskSession.completedEncouragement")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(HabitoAccessibilityID.completionCelebrationTitle)
            Text("taskSession.completedEncouragementDescription")
                .font(.title3)
            if isAutonomous {
                Label {
                    Text("taskSession.autonomyEncouragement")
                } icon: {
                    Image(systemName: "star.circle.fill").accessibilityHidden(true)
                }
                .font(.title3.bold())
                .padding(HabitoDesign.Spacing.small)
                .background(
                    tint.opacity(HabitoDesign.Feedback.badgeTintOpacity),
                    in: .rect(cornerRadius: HabitoDesign.CornerRadius.badge)
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(HabitoAccessibilityID.autonomyCelebration)
            }
            if !hasReward {
                Text("taskSession.effortWithoutCurrency")
                    .font(.body)
                    .accessibilityIdentifier(HabitoAccessibilityID.completionEffort)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        isAutonomous ? HabitoDesign.Feedback.autonomous : HabitoDesign.Feedback.completed
    }
}

#Preview("自主完成") {
    TaskCompletionCelebrationView(isAutonomous: true, hasReward: true).padding()
}

#Preview("零奖励 · 最大字号") {
    TaskCompletionCelebrationView(isAutonomous: false, hasReward: false)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
