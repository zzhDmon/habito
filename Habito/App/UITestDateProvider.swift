#if DEBUG
    import Foundation

    /// 将 UI 测试的真实经过时间映射到固定场景日期，不让午夜改变待验收场景。
    ///
    /// 测试进程只生成一次系统基准并通过启动环境传入；App 终止/重开仍沿用相同基准，
    /// 因而暂停、恢复和撤销窗口不会因重启发生时间倒退。正式构建不包含该类型。
    nonisolated struct UITestDateProvider: DateProviding {
        private let referenceSystemDate: Date
        private let referenceTestDate: Date
        private let systemDateProvider: any DateProviding

        /// 创建测试时钟；单测可替换底层系统时钟，不依赖真实等待。
        ///
        /// - Parameters:
        ///   - referenceSystemDate: 同一 UI 用例首次创建应用时的系统基准。
        ///   - referenceTestDate: 对应的固定场景日期，默认场景由启动配置提供。
        ///   - systemDateProvider: 实际经过时间的来源，正式 UI 自动化使用系统时钟边界。
        init(
            referenceSystemDate: Date, referenceTestDate: Date,
            systemDateProvider: any DateProviding = SystemDateProvider()
        ) {
            self.referenceSystemDate = referenceSystemDate
            self.referenceTestDate = referenceTestDate
            self.systemDateProvider = systemDateProvider
        }

        func now() -> Date {
            referenceTestDate.addingTimeInterval(systemDateProvider.now().timeIntervalSince(referenceSystemDate))
        }
    }
#endif
