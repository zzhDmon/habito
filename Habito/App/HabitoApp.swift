import SwiftData
import SwiftUI

/// Habito 的应用入口，同时也是依赖组合根。
///
/// V0 先在这里创建全局唯一的 SwiftData 容器。后续新增通知、时钟等系统服务时，
/// 也应在组合根完成装配，再通过环境或初始化参数传给功能模块，避免页面自行创建依赖。
@main
struct HabitoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let taskSessionModelFactory: TaskSessionViewModelFactory
    @State private var todayModel: TodayViewModel

    init() {
        let container: ModelContainer
        do {
            container = try AppModelContainer.make()
        } catch {
            // 持久化容器不可用时，继续运行会让后续读写行为不可预测，
            // 因此启动阶段直接失败并保留明确原因。
            fatalError("无法创建 Habito 数据容器：\(error.localizedDescription)")
        }
        modelContainer = container
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone.autoupdatingCurrent
        let dateProvider = SystemDateProvider()
        _todayModel = State(
            initialValue: TodayViewModel(
                context: container.mainContext,
                calendar: calendar,
                timeZone: timeZone,
                dateProvider: dateProvider
            )
        )
        taskSessionModelFactory = TaskSessionViewModelFactory(
            context: container.mainContext,
            calendar: calendar,
            timeZone: timeZone,
            dateProvider: dateProvider
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                todayModel: todayModel,
                taskSessionModelFactory: taskSessionModelFactory
            )
        }
        .modelContainer(modelContainer)
    }
}
