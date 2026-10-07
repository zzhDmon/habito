import SwiftUI

/// 将历史SF Symbols存储标识映射为同版Tabler资源；未知旧值使用清单，不迁移数据。
struct TaskIcon: View {
    let storedName: String
    @ScaledMetric(relativeTo: .title2) private var size = HabitoDesign.Manga.iconSize

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(HabitoDesign.Manga.ink)
            // 任务标题在相邻文本中，图标不重复朗读或暴露内部资源名。
            .accessibilityHidden(true)
    }

    private var assetName: String {
        switch storedName {
        case "book.fill": "TaskBook"
        case "pencil.line": "TaskPencil"
        case "figure.run": "TaskRun"
        case "music.note": "TaskMusic"
        default: "TaskChecklist"
        }
    }
}

#Preview("任务图标 · 未知值回退") {
    HStack {
        TaskIcon(storedName: "book.fill")
        TaskIcon(storedName: "unknown.legacy")
    }.padding()
}
