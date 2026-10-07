import Testing
@testable import Habito

@Suite("孩子昵称与单狗名字纯校验")
struct FamilyProfileNamesTests {
    @Test(
        "有效名字保留内部空格与 Unicode 原始字节",
        arguments: [
            "小 星星", "Alex Jr", "e\u{301}", "🐶🌟", "👨‍👩‍👧‍👦", "星\u{00A0}星",
        ])
    func validNamesPreserveInternalSpacesAndUnicode(_ input: String) throws {
        let names = try FamilyProfileNames(childNickname: input, petName: input)
        #expect(Array(names.childNickname.utf8) == Array(input.utf8))
        #expect(Array(names.petName.utf8) == Array(input.utf8))
    }

    @Test(
        "两端空白和换行被清理而不改变内部空格",
        arguments: [
            " ", "\t", "\r\n", "\u{00A0}", "\u{2028}", "\u{2029}",
        ])
    func surroundingWhitespaceIsTrimmed(_ padding: String) throws {
        let names = try FamilyProfileNames(
            childNickname: padding + "小 星星" + padding,
            petName: padding + "小 狗狗" + padding
        )
        #expect(names.childNickname == "小 星星")
        #expect(names.petName == "小 狗狗")
    }

    @Test("空昵称返回孩子字段错误", arguments: ["", " ", "\t\r\n", "\u{00A0}"])
    func blankChildNicknameIsRejected(_ input: String) {
        #expect(throws: FamilyProfileNameError.emptyChildNickname) {
            try FamilyProfileNames(childNickname: input, petName: "小狗狗")
        }
    }

    @Test("空狗名返回宠物字段错误", arguments: ["", " ", "\t\r\n", "\u{00A0}"])
    func blankPetNameIsRejected(_ input: String) {
        #expect(throws: FamilyProfileNameError.emptyPetName) {
            try FamilyProfileNames(childNickname: "小星星", petName: input)
        }
    }

    @Test(
        "内部行分隔符返回孩子字段错误",
        arguments: [
            "\r", "\n", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}",
        ])
    func interiorChildLineBreakIsRejected(_ separator: String) {
        #expect(throws: FamilyProfileNameError.lineBreakInChildNickname) {
            try FamilyProfileNames(childNickname: "小" + separator + "星星", petName: "小狗狗")
        }
    }

    @Test(
        "内部行分隔符返回宠物字段错误",
        arguments: [
            "\r", "\n", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}",
        ])
    func interiorPetLineBreakIsRejected(_ separator: String) {
        #expect(throws: FamilyProfileNameError.lineBreakInPetName) {
            try FamilyProfileNames(childNickname: "小星星", petName: "小" + separator + "狗狗")
        }
    }

    @Test("同时无效优先孩子字段且不代填")
    func bothInvalidFieldsReportChildErrorFirst() {
        #expect(throws: FamilyProfileNameError.emptyChildNickname) {
            try FamilyProfileNames(childNickname: "", petName: "")
        }
        #expect(throws: FamilyProfileNameError.lineBreakInChildNickname) {
            try FamilyProfileNames(childNickname: "小\n星星", petName: "")
        }
    }

    @Test("长输入不截断且不可变值可纯传递")
    func longNamesRemainIntactAndValuesAreSendable() throws {
        let input = String(repeating: "🌟小星星e\u{301}", count: 1_000)
        let names = try FamilyProfileNames(childNickname: input, petName: input)
        #expect(Array(names.childNickname.utf8) == Array(input.utf8))
        #expect(Array(names.petName.utf8) == Array(input.utf8))
        #expect(sendableIdentity(names) == names)
        #expect(try FamilyProfileNames(childNickname: " " + input, petName: input + " ") == names)
    }

    private func sendableIdentity<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
