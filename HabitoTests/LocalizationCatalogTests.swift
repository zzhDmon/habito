import Foundation
import Testing

struct LocalizationCatalogTests {
    @Test("每个字符串目录键都有非空简体中文值", arguments: ["Localizable", "UIR1"])
    func everyCatalogKeyHasSimplifiedChineseValue(table: String) throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL =
            testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Habito/Resources/\(table).xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)

        #expect(catalog.sourceLanguage == "zh-Hans")
        let missingKeys = catalog.strings.compactMap { key, entry in
            let value = entry.localizations?["zh-Hans"]?.stringUnit?.value
            return value?.isEmpty == false ? nil : key
        }.sorted()
        #expect(missingKeys.isEmpty, "缺少简体中文文案：\(missingKeys)")
    }
}

private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {
    let localizations: [String: StringCatalogLocalization]?
}

private struct StringCatalogLocalization: Decodable {
    let stringUnit: StringCatalogStringUnit?
}

private struct StringCatalogStringUnit: Decodable {
    let value: String
}
