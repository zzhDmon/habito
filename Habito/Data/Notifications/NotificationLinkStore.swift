import Foundation
import SwiftData

/// 集中维护 `NotificationLink`，保证系统请求标识、实例和通知用途始终一致。
@MainActor
struct NotificationLinkStore {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    /// 保存入口可由测试注入失败；正式实现仍使用原生 SwiftData，不在业务中直接模拟磁盘异常。
    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 创建或更新一个稳定通知槽位。
    ///
    /// 同一实例同一用途的旧格式映射会被替换；不同用途保留，因此主提醒和稍后提醒可共存。
    /// - Parameters:
    ///   - occurrenceID: 已入库实例的稳定标识。
    ///   - kind: 主提醒或稍后槽位，二者互不覆盖。
    ///   - scheduledAt: 本次排程的绝对触发时刻。
    ///   - createdAt: 仅用于首次创建，替换仍保留原时刻。
    ///   - submissionEpochUpdate: 重建保留原世代；明确新稍后替换世代，包括从未提交的 nil。
    /// - Returns: 同次保存成功的稳定槽位；保存失败不会返回收据。
    /// - Throws: 上下文有其他未保存编辑、目标不存在、槽位损坏或保存失败；不会报告虚假成功。
    @discardableResult
    func upsert(
        occurrenceID: UUID,
        kind: NotificationKind,
        scheduledAt: Date,
        createdAt: Date = .now,
        submissionEpochUpdate: NotificationSubmissionEpochUpdate = .preserve
    ) throws -> NotificationLink {
        // 映射是一笔独立事务，不能替调用方保存或回滚尚未确认的用户编辑。
        guard !context.hasChanges else { throw NotificationLinkStoreError.unsavedChanges }
        let originalAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = originalAutosave }
        var insertedLink: NotificationLink?
        var originalStable:
            (link: NotificationLink, scheduledAt: Date, occurrence: TaskOccurrence?, submissionID: UUID?)?
        do {
            let occurrence = try fetchOccurrence(id: occurrenceID)
            let identifier = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: kind)
            let existingLinks = try fetchLinks(occurrenceID: occurrenceID)
            let matchingKind = existingLinks.filter { $0.kindRawValue == kind.rawValue }

            if let stable = try fetchLink(requestIdentifier: identifier.rawValue) {
                guard stable.occurrenceID == occurrenceID, stable.kind == kind else {
                    throw NotificationLinkStoreError.inconsistentMapping(identifier: identifier.rawValue)
                }
                originalStable = (stable, stable.scheduledAt, stable.occurrence, stable.submissionIDAtScheduling)
                matchingKind.filter { $0 !== stable }.forEach(context.delete)
                stable.scheduledAt = scheduledAt
                stable.occurrence = occurrence
                apply(submissionEpochUpdate, to: stable)
                try saveChanges(context)
                return stable
            }

            matchingKind.forEach(context.delete)
            let link = NotificationLink(
                requestIdentifier: identifier.rawValue,
                occurrenceID: occurrenceID,
                kind: kind,
                scheduledAt: scheduledAt,
                createdAt: createdAt
            )
            context.insert(link)
            insertedLink = link
            // 17 必须先建立上下文归属，再连已入库实例；否则失败回滚可能留下自动插入的孤立映射。
            link.occurrence = occurrence
            apply(submissionEpochUpdate, to: link)
            try saveChanges(context)
            return link
        } catch {
            // 新关系先断开，再撤销本事务插入；不靠补偿保存掩盖第一次失败。
            insertedLink?.occurrence = nil
            if let originalStable {
                // 17 磁盘路径 rollback 不一定同步 Swift 标量缓存；先恢复本事务原值，再撤销持久化写。
                originalStable.link.scheduledAt = originalStable.scheduledAt
                originalStable.link.submissionIDAtScheduling = originalStable.submissionID
                originalStable.link.occurrence = originalStable.occurrence
            }
            context.rollback()
            throw error
        }
    }

    /// 以系统请求标识反查并验证映射。
    func link(requestIdentifier: String) throws -> NotificationLink? {
        guard let identifier = NotificationRequestIdentifier(rawValue: requestIdentifier) else {
            throw NotificationLinkStoreError.invalidIdentifier(requestIdentifier)
        }
        guard let link = try fetchLink(requestIdentifier: requestIdentifier) else { return nil }
        try validate(link, expected: identifier)
        return link
    }

    /// 返回实例的全部映射；任何损坏值都会显式失败，避免后续误删其他请求。
    func links(occurrenceID: UUID) throws -> [NotificationLink] {
        let links = try fetchLinks(occurrenceID: occurrenceID)
        for link in links {
            guard let identifier = NotificationRequestIdentifier(rawValue: link.requestIdentifier) else {
                throw NotificationLinkStoreError.invalidIdentifier(link.requestIdentifier)
            }
            try validate(link, expected: identifier)
        }
        return links.sorted { $0.requestIdentifier < $1.requestIdentifier }
    }

    /// 删除一个稳定槽位；不存在时保持幂等。
    func remove(occurrenceID: UUID, kind: NotificationKind) throws {
        do {
            let identifier = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: kind)
            if let link = try fetchLink(requestIdentifier: identifier.rawValue) {
                try validate(link, expected: identifier)
                context.delete(link)
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 更新世代与槽位时间同次保存；普通重建不能把旧请求改称新轮次的请求。
    private func apply(_ update: NotificationSubmissionEpochUpdate, to link: NotificationLink) {
        if case let .replace(id) = update { link.submissionIDAtScheduling = id }
    }

    private func fetchOccurrence(id: UUID) throws -> TaskOccurrence {
        let descriptor = FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == id })
        guard let occurrence = try context.fetch(descriptor).first else {
            throw NotificationLinkStoreError.occurrenceNotFound(id)
        }
        return occurrence
    }

    private func fetchLink(requestIdentifier: String) throws -> NotificationLink? {
        let descriptor = FetchDescriptor<NotificationLink>(
            predicate: #Predicate { $0.requestIdentifier == requestIdentifier }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchLinks(occurrenceID: UUID) throws -> [NotificationLink] {
        let descriptor = FetchDescriptor<NotificationLink>(
            predicate: #Predicate { $0.occurrenceID == occurrenceID }
        )
        return try context.fetch(descriptor)
    }

    private func validate(
        _ link: NotificationLink,
        expected identifier: NotificationRequestIdentifier
    ) throws {
        guard let kind = link.kind else {
            throw NotificationLinkStoreError.invalidKind(
                identifier: link.requestIdentifier,
                rawValue: link.kindRawValue
            )
        }
        guard
            link.occurrenceID == identifier.occurrenceID,
            kind == identifier.kind,
            link.occurrence?.id == identifier.occurrenceID
        else {
            throw NotificationLinkStoreError.inconsistentMapping(identifier: link.requestIdentifier)
        }
    }
}
