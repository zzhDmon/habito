import Foundation
import Observation
import OSLog
import SwiftData

/// 主 actor 内协调队列与审核事务；PIN 权限由家长组合根与受保护导航负责。
///
/// View 只转交捕获的纯值请求。重新取实例但始终使用原提交 ID，不自动审核最新轮次。
/// @Observable 让页面只订阅它读取的队列/错误/反馈；生命周期由受保护页面持有，不保存成历史庆祝。
@MainActor
@Observable
final class ParentReviewViewModel {
    private(set) var state: ParentReviewViewState = .loading
    private(set) var feedback: ParentReviewFeedback?
    private(set) var actionFailure: ParentReviewActionFailure?
    var isActionErrorPresented = false

    private let context: ModelContext
    private let queueService: ParentReviewQueueService
    private let reviewService: TaskSubmissionReviewService
    private let dateProvider: any DateProviding
    private let notificationRebuildTrigger: NotificationRebuildTrigger
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ParentReview")

    init(
        context: ModelContext, dateProvider: any DateProviding,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger(),
        reviewService: TaskSubmissionReviewService? = nil
    ) {
        self.context = context
        queueService = ParentReviewQueueService(context: context)
        self.reviewService = reviewService ?? TaskSubmissionReviewService(context: context)
        self.dateProvider = dateProvider
        self.notificationRebuildTrigger = notificationRebuildTrigger
    }

    func load() {
        reload(showLoading: true)
    }

    /// 每次进入受保护页面开启新的展示周期，不重播上次页面保留的成功收据。
    func prepareForPresentation() {
        feedback = nil
        actionFailure = nil
        isActionErrorPresented = false
        load()
    }

    func refresh() {
        reload(showLoading: false)
    }

    /// 通过捕获的原提交；仅新保存成功产生反馈与通知事件。
    func approve(_ item: ParentReviewQueueItem) {
        perform(item, outcome: .approved)
    }

    /// 退回捕获的原提交，不删计时/历史、不扣奖励。
    func returnForRevision(_ item: ParentReviewQueueItem) {
        perform(item, outcome: .returned)
    }

    func dismissFeedback() {
        feedback = nil
    }

    private func perform(_ item: ParentReviewQueueItem, outcome: SubmissionReviewState) {
        do {
            let occurrenceID = item.occurrenceID
            let occurrences = try context.fetch(
                FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == occurrenceID }))
            guard let occurrence = occurrences.first else {
                throw ParentReviewQueueError.occurrenceNotFound(occurrenceID)
            }
            let result: TaskSubmissionReviewResult
            switch outcome {
            case .approved:
                result = try reviewService.approve(occurrence, submissionID: item.id, at: dateProvider.now())
            case .returned:
                result = try reviewService.returnForRevision(occurrence, submissionID: item.id, at: dateProvider.now())
            case .waiting:
                return
            }
            if result.didReview {
                feedback = ParentReviewFeedback(occurrenceID: occurrence.id, result: result)
                notificationRebuildTrigger.requestRebuild()
            }
            actionFailure = nil
            isActionErrorPresented = false
            reload(showLoading: false)
        } catch {
            logger.error("家长审核失败：\(String(describing: type(of: error)), privacy: .public)")
            switch error {
            case TaskSubmissionReviewError.submissionNotFound, TaskSubmissionReviewError.conflictingOutcome:
                actionFailure = .changedSubmission
            case is ParentReviewQueueError, is TaskSubmissionReviewError, is TaskSubmissionError,
                is TaskCompletionServiceError, is TaskProgressServiceError, is RewardLedgerError:
                actionFailure = .unavailable
            default:
                actionFailure = .saveFailed
            }
            // 原事务失败不能被“已通过”替代，也不丢掉现有队列让家长误以为没有待审核项。
            isActionErrorPresented = true
        }
    }

    private func reload(showLoading: Bool) {
        if showLoading { state = .loading }
        do {
            let items = try queueService.items()
            if let feedback, try !queueService.isCurrent(feedback) { self.feedback = nil }
            state = .loaded(items)
        } catch {
            logger.error("家长审核队列读取失败：\(String(describing: type(of: error)), privacy: .public)")
            feedback = nil
            state = .failed
        }
    }
}
