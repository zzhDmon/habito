import Foundation
import SwiftData

/// 集中维护 `NotificationLink`，保证系统请求标识、实例和通知用途始终一致。
@MainActor
struct NotificationLinkStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 创建或更新一个稳定通知槽位。
    ///
    /// 同一实例同一用途的旧格式映射会被替换；不同用途保留，因此主提醒和稍后提醒可共存。
    @discardableResult
    func upsert(
        occurrenceID: UUID,
        kind: NotificationKind,
        scheduledAt: Date,
        createdAt: Date = .now
    ) throws -> NotificationLink {
        do {
            let occurrence = try fetchOccurrence(id: occurrenceID)
            let identifier = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: kind)
            let existingLinks = try fetchLinks(occurrenceID: occurrenceID)
            let matchingKind = existingLinks.filter { $0.kindRawValue == kind.rawValue }

            if let stable = try fetchLink(requestIdentifier: identifier.rawValue) {
                guard stable.occurrenceID == occurrenceID, stable.kind == kind else {
                    throw NotificationLinkStoreError.inconsistentMapping(identifier: identifier.rawValue)
                }
                matchingKind.filter { $0 !== stable }.forEach(context.delete)
                stable.scheduledAt = scheduledAt
                stable.occurrence = occurrence
                try context.save()
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
            link.occurrence = occurrence
            context.insert(link)
            try context.save()
            return link
        } catch {
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
