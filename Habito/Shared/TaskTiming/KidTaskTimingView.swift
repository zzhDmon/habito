import SwiftUI

/// 系统只负责前台刷新节奏，业务时刻仍由页面模型的注入时钟提供。
///
/// 只有可执行且设置了截止的任务才使用 `TimelineView`，随视图生命周期刷新；
/// 其余时间文字使用静态子视图，避免普通任务清单持有无意义的定时更新。
/// 不以系统日期判断业务，也不依赖后台 tick 维持事实；不查询、排序、写库或发奖。
struct KidTaskTimingView: View {
    let makePresentation: @MainActor () -> KidTaskTimingPresentation

    var body: some View {
        let presentation = makePresentation()
        if presentation.needsDeadlineRefresh {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                KidTaskTimingDetails(presentation: makePresentation())
            }
        } else {
            KidTaskTimingDetails(presentation: presentation)
        }
    }
}
