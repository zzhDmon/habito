import SwiftUI

#Preview("Parent calendar") {
    ParentCalendarDayPreview()
}

/// 在内存容器中展示日历页，预览失败不会污染正式数据。
@MainActor
private struct ParentCalendarDayPreview: View {
    private let model: ParentCalendarDayViewModel?

    init() {
        do {
            let container = try AppModelContainer.make(inMemory: true)
            model = ParentCalendarDayViewModel(
                context: container.mainContext,
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .gmt,
                dateProvider: SystemDateProvider()
            )
        } catch {
            model = nil
        }
    }

    var body: some View {
        NavigationStack {
            if let model {
                ParentCalendarDayView(model: model)
            } else {
                ContentUnavailableView(
                    "parentCalendar.errorTitle",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }
}
