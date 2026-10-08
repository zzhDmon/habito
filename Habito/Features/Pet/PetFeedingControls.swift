import SwiftUI

/// 喂食必须明确展示价格及效果；已保存收据与失败分开，失败按钮继续使用原请求。
struct PetFeedingControls: View {
    let model: PetProfileViewModel
    let canFeed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text("pet.foodTitle", tableName: "UIR1").font(.headline)
            Text(
                String.localizedStringWithFormat(
                    String(localized: "pet.foodDescriptionFormat", table: "UIR1"), PetCareRules.foodCost,
                    PetCareRules.feedingBondGain))
            if let receipt = model.feedingReceipt {
                Text("pet.fed", tableName: "UIR1").font(.title3.bold())
                    .accessibilityIdentifier(HabitoAccessibilityID.petFed)
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "pet.fedDetailFormat", table: "UIR1"), receipt.coinCost, receipt.bondGain))
                Button(action: model.dismissFeedingReceipt) { Text("pet.continue", tableName: "UIR1") }
                    .buttonStyle(MangaButtonStyle()).accessibilityIdentifier(HabitoAccessibilityID.petFedContinue)
            } else {
                if let error = model.feedingError {
                    errorText(error).accessibilityIdentifier(HabitoAccessibilityID.petFeedError)
                }
                if !canFeed { Text("pet.notEnough", tableName: "UIR1") }
                Button(action: model.feed) { Text("pet.feed", tableName: "UIR1") }
                    .buttonStyle(MangaButtonStyle()).disabled(!canFeed)
                    .accessibilityIdentifier(HabitoAccessibilityID.petFeed)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func errorText(_ error: PetFeedingFailure) -> Text {
        switch error {
        case .insufficientCoins: Text("pet.notEnough", tableName: "UIR1")
        case .clockReversed: Text("pet.clockError", tableName: "UIR1")
        case .saveFailed: Text("pet.saveError", tableName: "UIR1")
        case .unavailable: Text("pet.unavailable", tableName: "UIR1")
        }
    }
}
