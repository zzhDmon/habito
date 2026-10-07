import SwiftUI

/// 仅由已解锁家长路由创建；出现及前台恢复重读，不在构造或孩子首页加载历史。
struct GrowthStatisticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GrowthStatisticsViewModel

    init(model: GrowthStatisticsViewModel) { _model = State(initialValue: model) }

    var body: some View {
        GrowthStatisticsBody(state: model.state, period: model.period, onSelect: model.select, onRetry: model.load)
            .navigationTitle("statistics.navigationTitle")
            .task(model.load)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.load() }
            }
    }
}
