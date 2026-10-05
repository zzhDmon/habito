/// 儿童首页的语义分组，不从某个提醒小时猜分类；旧任务默认全天。
nonisolated enum TaskTimePeriod: String, CaseIterable, Sendable {
    case morning
    case afterSchool
    case evening
    case allDay
}
