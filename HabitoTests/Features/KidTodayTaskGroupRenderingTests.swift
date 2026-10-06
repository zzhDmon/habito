import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("儿童时间段展示原生渲染")
struct KidTodayTaskGroupRenderingTests {
    @Test("旧 nil 或三种时间提示在普通和最大字号均可原生渲染", arguments: [false, true], [false, true])
    func timingDetailsRenderAtBothTextSizes(threeTimes: Bool, large: Bool) throws {
        let task: KidTaskNavigationItem = threeTimes ? .previewThreeTimes : .previewReading
        let renderer = ImageRenderer(
            content: KidTaskTimingDetails(presentation: .preview(for: task))
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                .frame(width: 320))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height > 0)
    }

    @Test("四时段与跨日在普通和最大字号均可渲染", arguments: TodayTaskGroupKind.displayOrder, [false, true])
    func groupsRenderAtBothTextSizes(kind: TodayTaskGroupKind, large: Bool) throws {
        let period: TaskTimePeriod
        switch kind {
        case .carryOver: period = .allDay
        case let .timePeriod(value): period = value
        }
        let task = KidTaskNavigationItem(
            id: UUID(), title: String(localized: "kidTask.previewTitle"), iconName: "book.fill",
            scheduledTimeText: "19:30", targetDurationText: String(localized: "kidTask.previewDuration"),
            status: .inProgress, statusText: String(localized: "kidTask.statusInProgress"),
            statusIconName: "play.circle.fill", timePeriod: period, isCarryOver: kind == .carryOver)
        let renderer = ImageRenderer(
            content: VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                KidTodayTaskGroupView(
                    group: TodayTaskGroup(id: kind, tasks: [task]),
                    makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in })
            }
            .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
            .frame(width: 320))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height > 0)
    }

    @Test("五种组标题身份稳定且互不重复，不用中文文案或遍历序号")
    func groupTitleIdentifiersAreStableAndDistinct() {
        let ids = TodayTaskGroupKind.displayOrder.map(HabitoAccessibilityID.todayTaskGroupTitle)
        #expect(Set(ids).count == 5)
        #expect(
            ids == [
                "kid.today.group.carry-over", "kid.today.group.morning", "kid.today.group.afterSchool",
                "kid.today.group.evening", "kid.today.group.allDay",
            ])
    }
}
