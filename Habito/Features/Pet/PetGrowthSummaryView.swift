import SwiftUI

/// 当前成长信息由服务计算；低龄文案说明金币价格和亲密度效果，不以颜色表达心情。
struct PetGrowthSummaryView: View {
    let snapshot: PetCareSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text(String.localizedStringWithFormat(String(localized: "pet.levelFormat", table: "UIR1"), snapshot.level))
                .font(.title2.bold()).accessibilityIdentifier(HabitoAccessibilityID.petLevel)
            ProgressView(value: Double(snapshot.xpInLevel), total: Double(PetCareRules.xpPerLevel)) {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "pet.nextXPFormat", table: "UIR1"), snapshot.xpToNextLevel))
            }.tint(HabitoDesign.Manga.successInk)
            Text(String.localizedStringWithFormat(String(localized: "pet.bondFormat", table: "UIR1"), snapshot.bond))
                .accessibilityIdentifier(HabitoAccessibilityID.petBond)
            // 静态分支明确指定目录，避免编译器将条件字符串提取为默认表中的空键。
            Group {
                if snapshot.mood == .happy {
                    Text("pet.happy", tableName: "UIR1")
                } else {
                    Text("pet.calm", tableName: "UIR1")
                }
            }
            .accessibilityIdentifier(HabitoAccessibilityID.petMood)
            Text(String.localizedStringWithFormat(String(localized: "pet.coinsFormat", table: "UIR1"), snapshot.coins))
                .accessibilityIdentifier(HabitoAccessibilityID.petCoins)
            Text("pet.noPenalty", tableName: "UIR1").font(.callout).foregroundStyle(HabitoDesign.Manga.secondaryInk)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("成长 · 深色大字") {
    PetHomeView(model: PetPreviewData.model(kind: 1), onOpenParent: {})
        .environment(\.dynamicTypeSize, .accessibility5).preferredColorScheme(.dark).padding()
}
