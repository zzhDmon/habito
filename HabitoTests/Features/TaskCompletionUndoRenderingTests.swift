import SwiftUI
import Testing
@testable import Habito

@MainActor
struct TaskCompletionUndoRenderingTests {
    @Test("固定撤销条在最后一秒与MAX仍可自然渲染", arguments: [1, 5], [false, true])
    func undoBarRenders(seconds: Int, maximumTextSize: Bool) throws {
        let renderer = ImageRenderer(
            content: TaskCompletionUndoView(remainingSeconds: seconds, onUndo: {})
                .environment(\.dynamicTypeSize, maximumTextSize ? .accessibility5 : .large).frame(width: 320))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height >= 44)
    }
}
