import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("名字设置页面状态")
struct FamilyProfileEditorViewModelTests {
    @Test("构造与关闭清理不读取或写入资料")
    func constructionAndResetDoNotAccessData() {
        let model = FamilyProfileEditorViewModel(
            loadNames: {
                Issue.record("构造或清理不能预读取")
                return nil
            },
            saveNames: { _ in
                Issue.record("构造或清理不能保存")
                return false
            })
        #expect(model.loadState == .idle && model.feedback == nil)
        #expect(model.childNickname.isEmpty && model.petName.isEmpty && !model.hasStoredNames)
        model.childNickname = "合成未保存输入"
        model.reset()
        #expect(model.loadState == .idle && model.childNickname.isEmpty && model.petName.isEmpty)
    }

    @Test("真实未设置或已有资料只在显式载入时回读", arguments: [false, true])
    func explicitLoadUsesRealService(configured: Bool) throws {
        let context = try makeContext()
        let service = FamilyProfileService(context: context)
        let value = try names()
        if configured { try service.save(value) }
        let model = FamilyProfileEditorViewModel(loadNames: service.load, saveNames: service.save)
        #expect(model.loadState == .idle)
        model.load()
        #expect(model.loadState == .ready && model.hasStoredNames == configured)
        #expect(model.childNickname == (configured ? value.childNickname : ""))
        #expect(model.petName == (configured ? value.petName : ""))
        #expect(!context.hasChanges)
    }

    @Test("重复载入和正常态重试不覆草稿，关闭后重新读取最新资料")
    func repeatedLoadPreservesDraftAndResetAllowsFreshLoad() throws {
        var stored = try names()
        var reads = 0
        let model = FamilyProfileEditorViewModel(
            loadNames: {
                reads += 1
                return stored
            }, saveNames: { _ in false })
        model.load()
        model.childNickname = "尚未保存的昵称"
        model.petName = "尚未保存的狗名"
        stored = try names(updated: true)
        model.load()
        model.retryLoad()
        #expect(reads == 1 && model.childNickname == "尚未保存的昵称" && model.petName == "尚未保存的狗名")
        model.reset()
        #expect(model.loadState == .idle && model.feedback == nil && !model.hasStoredNames)
        #expect(model.childNickname.isEmpty && model.petName.isEmpty)
        model.load()
        #expect(reads == 2 && model.childNickname == stored.childNickname && model.petName == stored.petName)
    }

    @Test(
        "空与内部换行反馈准确字段并保留草稿不保存",
        arguments: [
            FamilyProfileNameError.emptyChildNickname, .emptyPetName, .lineBreakInChildNickname, .lineBreakInPetName,
        ])
    func invalidInputIsReportedWithoutSaving(_ error: FamilyProfileNameError) {
        let model = FamilyProfileEditorViewModel(
            loadNames: { nil },
            saveNames: { _ in
                Issue.record("校验失败不能保存")
                return false
            })
        model.load()
        model.childNickname = "合成昵称"
        model.petName = "合成狗名"
        switch error {
        case .emptyChildNickname: model.childNickname = " "
        case .emptyPetName: model.petName = " "
        case .lineBreakInChildNickname: model.childNickname = "合成\n昵称"
        case .lineBreakInPetName: model.petName = "合成\n狗名"
        }
        let enteredChild = model.childNickname
        let enteredPet = model.petName
        #expect(!model.save() && model.feedback == .validation(error))
        #expect(model.childNickname == enteredChild && model.petName == enteredPet)
        #expect(!model.hasStoredNames && !model.isSaving && model.loadState == .ready)
    }

    @Test("未载入或载入失败禁止保存，明确重试后才可编辑保存")
    func failedLoadDoesNotBecomeBlankCreationAndCanRetry() throws {
        var fails = true
        var reads = 0
        var saves = 0
        let value = try names()
        let model = FamilyProfileEditorViewModel(
            loadNames: {
                reads += 1
                if fails { throw FamilyProfileServiceError.invalidStoredNames }
                return value
            },
            saveNames: { _ in
                saves += 1; return false
            })
        #expect(!model.save() && reads == 0 && saves == 0)
        model.load()
        #expect(model.loadState == .failed && !model.save() && saves == 0)
        model.load()
        #expect(reads == 1)
        fails = false
        model.retryLoad()
        #expect(reads == 2 && model.loadState == .ready && model.hasStoredNames)
        #expect(model.childNickname == value.childNickname && model.petName == value.petName)
        #expect(model.save() && model.feedback == .saved && saves == 1)
    }

    @Test("真实保存失败保留原文草稿和旧资料，重试成功才规范化输入")
    func failedSavePreservesDraftAndStoredNamesUntilRetry() throws {
        let context = try makeContext()
        let normal = FamilyProfileService(context: context)
        let original = try names()
        try normal.save(original)
        var fails = true
        let service = FamilyProfileService(
            context: context,
            saveChanges: { context in
                if fails { throw NSError(domain: "HabitoSyntheticEditorSave", code: 1) }
                try context.save()
            })
        let model = FamilyProfileEditorViewModel(loadNames: service.load, saveNames: service.save)
        model.load()
        model.childNickname = "  新 小星星e\u{301}  "
        model.petName = "  新🐶狗狗  "
        #expect(!model.save() && model.feedback == .storageFailure)
        #expect(model.childNickname == "  新 小星星e\u{301}  " && model.petName == "  新🐶狗狗  ")
        #expect(try normal.load() == original && !context.hasChanges && !model.isSaving)
        fails = false
        #expect(model.save() && model.feedback == .saved && model.hasStoredNames)
        #expect(model.childNickname == "新 小星星e\u{301}" && model.petName == "新🐶狗狗")
        let stored = try #require(try normal.load())
        #expect(Array(stored.childNickname.utf8) == Array(model.childNickname.utf8))
        model.reset()
        #expect(model.feedback == nil && model.childNickname.isEmpty && model.petName.isEmpty)
    }

    @Test("真实同值幂等保存仍回馈成功但不再次写库")
    func idempotentSaveStillConfirmsStoredFact() throws {
        let context = try makeContext()
        var writes = 0
        let service = FamilyProfileService(
            context: context,
            saveChanges: { context in
                writes += 1
                try context.save()
            })
        let model = FamilyProfileEditorViewModel(loadNames: service.load, saveNames: service.save)
        model.load()
        let value = try names()
        model.childNickname = value.childNickname
        model.petName = value.petName
        #expect(model.save())
        #expect(model.save() && model.feedback == .saved && model.hasStoredNames && writes == 1)
        #expect(!context.hasChanges)
    }

    @Test("同步保存期间的重入意图不会再次调用保存边界")
    func reentrantSaveIsRejected() throws {
        weak var activeModel: FamilyProfileEditorViewModel?
        var saves = 0
        let model = FamilyProfileEditorViewModel(
            loadNames: { nil },
            saveNames: { _ in
                saves += 1
                if let activeModel {
                    #expect(activeModel.isSaving && !activeModel.save())
                }
                return true
            })
        activeModel = model
        model.load()
        let value = try names()
        model.childNickname = value.childNickname
        model.petName = value.petName
        #expect(model.save() && saves == 1 && !model.isSaving)
    }

    @Test("编辑任一名字撤下旧成功或校验反馈，不把新草稿说成已保存", arguments: [false, true], [false, true])
    func editingClearsObsoleteFeedback(childField: Bool, successful: Bool) throws {
        let model = FamilyProfileEditorViewModel(loadNames: { nil }, saveNames: { _ in false })
        model.load()
        let value = try names()
        model.childNickname = successful ? value.childNickname : ""
        model.petName = value.petName
        #expect(model.save() == successful)
        let previous = model.feedback
        #expect(previous != nil)
        let sameChild = model.childNickname
        model.childNickname = sameChild
        #expect(model.feedback == previous)
        if childField { model.childNickname = "新草稿昵称" } else { model.petName = "新草稿狗名" }
        #expect(model.feedback == nil && model.loadState == .ready)
    }

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    private func names(updated: Bool = false) throws -> FamilyProfileNames {
        try FamilyProfileNames(childNickname: updated ? "新 小星星" : "小 星星", petName: updated ? "新🐶狗狗" : "🐶狗狗")
    }
}
