import SwiftUI

/// 印章保留完整中文语义，不依赖颜色或仅有英文拟声词表达完成。
struct MangaStamp: View {
    let title: LocalizedStringKey
    var systemImage = "checkmark.seal.fill"

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.heavy))
            .foregroundStyle(HabitoDesign.Manga.successInk)
            .padding(HabitoDesign.Spacing.small)
            .modifier(MangaPanel(fill: HabitoDesign.Manga.successPaper))
    }
}

#Preview("完成印章") {
    MangaStamp(title: "kidTask.statusCompleted").padding()
}
