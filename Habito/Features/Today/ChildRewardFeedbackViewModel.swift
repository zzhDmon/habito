import Foundation
import Observation
import OSLog

/// 主 actor 管理真实收据的展示生命周期；导航、刷新和退出都不自动确认已读。
@MainActor
@Observable
final class ChildRewardFeedbackViewModel {
    private(set) var state: ChildRewardFeedbackState = .idle
    private(set) var acknowledgementFailed = false
    private let service: ChildRewardReceiptService
    private let dateProvider: any DateProviding
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ChildRewardFeedback")

    init(service: ChildRewardReceiptService, dateProvider: any DateProviding) {
        self.service = service
        self.dateProvider = dateProvider
    }

    /// 每次返回首页或进入前台重新验证收据；同一完成 ID 保持视觉事件，不重复结算。
    func load() {
        let previous = currentReceipt
        do {
            let receipts = try service.pendingReceipts()
            // 保持孩子正在读的那一条；新加入的跨日收据不抢走当前反馈。
            let next = receipts.first { $0.id == previous?.id } ?? receipts.first
            state = next.map(ChildRewardFeedbackState.receipt) ?? .idle
            if next?.id != previous?.id { acknowledgementFailed = false }
        } catch {
            state = .failed
            acknowledgementFailed = false
            record(error)
        }
    }

    /// 只响应按钮捕获的当前完成 ID，防止连续点击把下一条尚未读的收据也确认掉。
    ///
    /// - Important: 保存失败保留原收据及错误，继续按钮可重试；成功后才读取下一条。
    func acknowledge(completionID: UUID) {
        guard currentReceipt?.id == completionID else { return }
        do {
            _ = try service.acknowledge(completionID: completionID, at: dateProvider.now())
            state = .idle
            acknowledgementFailed = false
            load()
        } catch let error as ChildRewardReceiptError {
            // 已撤销或被移除的陈旧页面不能继续庆祝，也不能替换成下一轮完成 ID。
            switch error {
            case .completionNotFound, .unavailableReceipt, .invalidDeliveryMetadata:
                state = .failed
                acknowledgementFailed = false
            case .acknowledgementBeforeSettlement:
                acknowledgementFailed = true
            }
            record(error)
        } catch let error as RewardLedgerError {
            // 账本或时间快照已无法验证，撤下旧金额；保存失败才保留可重试的原收据。
            state = .failed
            acknowledgementFailed = false
            record(error)
        } catch let error as TaskCompletionServiceError {
            state = .failed
            acknowledgementFailed = false
            record(error)
        } catch {
            acknowledgementFailed = true
            record(error)
        }
    }

    private var currentReceipt: ChildRewardReceipt? {
        guard case let .receipt(receipt) = state else { return nil }
        return receipt
    }

    private func record(_ error: any Error) {
        // 日志仅保留错误类型，不记录任务标题、家庭数据或 PIN。
        logger.error("儿童收据操作失败：\(String(describing: type(of: error)), privacy: .public)")
    }
}
