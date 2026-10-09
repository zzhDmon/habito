import SwiftUI

/// 本地专属品牌标记；画像只作装饰，不替代家长保存的昵称或操作标签。
struct ChildIdentityBadge: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: HabitoDesign.Spacing.medium) {
            // 小尺寸图像使用独立降采样资产，不在每次布局时解码应用图标的大图。
            Image(decorative: "YihePortrait")
                .resizable()
                .scaledToFit()
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 56 : 72)
                .clipShape(.rect(cornerRadius: HabitoDesign.Spacing.medium))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                Text("brand.name", tableName: "UIR1")
                    .font(.title2.bold())
                    .accessibilityIdentifier("brand.identity.title")
                Text("brand.tagline", tableName: "UIR1")
                    .font(.callout)
                    .foregroundStyle(HabitoDesign.Manga.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(HabitoDesign.Manga.ink)
    }
}

#Preview("一禾 · 品牌") {
    ChildIdentityBadge().padding().background(HabitoDesign.Manga.warmPaper)
}

#Preview("一禾 · 深色最大字号") {
    ChildIdentityBadge().padding().frame(width: 360)
        .environment(\.dynamicTypeSize, .accessibility5).preferredColorScheme(.dark)
}
