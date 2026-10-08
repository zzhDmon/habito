#if DEBUG
    import Foundation
    import SwiftData

    /// 故障探针需显式隔离及故障双标志；重试回到真实服务，Release不编译此类型。
    @MainActor
    enum UITestPetProfileFactory {
        static let readFailureArgument = "--habito-ui-pet-read-fail-once"
        static let feedFailureArgument = "--habito-ui-pet-feed-fail-once"

        static func make(
            context: ModelContext, arguments: [String], calendar: Calendar, timeZone: TimeZone,
            now: @escaping () -> Date
        ) -> PetProfileViewModel {
            let isolated = arguments.contains(UITestLaunchConfiguration.enableArgument)
            var shouldFailRead = isolated && arguments.contains(readFailureArgument)
            var shouldFailFeed = isolated && arguments.contains(feedFailureArgument)
            let service = PetCareService(
                context: context, calendar: calendar, timeZone: timeZone,
                saveChanges: { context in
                    if shouldFailFeed { shouldFailFeed = false; throw CocoaError(.fileWriteUnknown) }
                    try context.save()
                })
            return PetProfileViewModel(
                loadSnapshot: { date in
                    if shouldFailRead { shouldFailRead = false; throw CocoaError(.fileReadUnknown) }
                    return try service.load(at: date)
                }, feedPet: service.feed, now: now)
        }
    }
#endif
