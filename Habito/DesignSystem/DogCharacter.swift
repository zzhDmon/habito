import SwiftUI

/// 默认角色只作为陪伴插画，不暗示未实现的饥饿、等级或心情事实。
struct DogCharacter: View {
    var body: some View {
        Image(decorative: "DogDefault")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: HabitoDesign.Manga.characterHeight)
            .accessibilityHidden(true)
    }
}

#Preview("小狗 · 透明背景") {
    DogCharacter().padding().background(HabitoDesign.Manga.warmPaper)
}
