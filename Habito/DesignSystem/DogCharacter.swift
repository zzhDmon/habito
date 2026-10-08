import SwiftUI

/// 陪伴/庆祝角色只作插画；庆祝资格由宿主事实决定，不暗示饥饿、等级或心情数值。
struct DogCharacter: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var celebrating = false

    var body: some View {
        // 最大字号把空间留给真实状态与操作；缺少插画不影响任何任务或奖励信息。
        if !dynamicTypeSize.isAccessibilitySize {
            Image(decorative: celebrating ? "DogCelebrate" : "DogDefault")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: HabitoDesign.Manga.characterHeight)
                .accessibilityHidden(true)
        }
    }
}

#Preview("小狗 · 透明背景") {
    DogCharacter().padding().background(HabitoDesign.Manga.warmPaper)
}
