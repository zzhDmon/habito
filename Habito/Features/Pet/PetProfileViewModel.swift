import Foundation
import Observation
import OSLog

/// 主actor展示真实宠物状态；View仅转发意图，稳定请求ID跨失败重试保留。
@MainActor
@Observable
final class PetProfileViewModel {
    private(set) var state: PetProfileViewState = .loading
    private(set) var feedingReceipt: PetFeedingReceipt?
    private(set) var feedingError: PetFeedingFailure?
    private let loadSnapshot: (Date) throws -> PetCareSnapshot?
    private let feedPet: (UUID, Date) throws -> PetFeedingReceipt
    private let now: () -> Date
    private let makeRequestID: () -> UUID
    private var pendingRequestID: UUID?
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "PetProfile")

    /// 构造不读库；服务和时间从组合根注入，预览和测试无需正式容器。
    init(
        loadSnapshot: @escaping (Date) throws -> PetCareSnapshot?,
        feedPet: @escaping (UUID, Date) throws -> PetFeedingReceipt,
        now: @escaping () -> Date, makeRequestID: @escaping () -> UUID = UUID.init
    ) {
        self.loadSnapshot = loadSnapshot
        self.feedPet = feedPet
        self.now = now
        self.makeRequestID = makeRequestID
    }

    /// 进入、前台和家长关闭时刷新；错误撤下旧资产，不影响尚未成功的请求ID。
    func load() {
        feedingReceipt = nil
        feedingError = nil
        refresh()
    }

    /// 成功后先要求“知道了”，连续点击同一按钮不能意外购买第二份。
    func feed() {
        guard case .loaded = state, feedingReceipt == nil else { return }
        let id = pendingRequestID ?? makeRequestID()
        pendingRequestID = id
        feedingError = nil
        do {
            let receipt = try feedPet(id, now())
            feedingReceipt = receipt
            pendingRequestID = nil
            refresh()
        } catch let error as RewardLedgerError {
            if case .insufficientCoins = error {
                feedingError = .insufficientCoins
            } else {
                feedingError = .unavailable
            }
            record(error)
            refresh()
        } catch let error as PetCareError {
            feedingError = error == .timeBeforeLatestFeeding ? .clockReversed : .unavailable
            record(error)
            refresh()
        } catch {
            feedingError = .saveFailed
            record(error)
            // 保存失败只保留原快照和请求，不假定已经扣款或播放成功。
        }
    }

    func dismissFeedingReceipt() { feedingReceipt = nil }

    private func refresh() {
        do {
            state = try loadSnapshot(now()).map(PetProfileViewState.loaded) ?? .notConfigured
        } catch {
            state = .failed
            record(error)
        }
    }

    private func record(_ error: any Error) {
        logger.error("小狗操作失败：\(String(describing: type(of: error)), privacy: .public)")
    }
}
