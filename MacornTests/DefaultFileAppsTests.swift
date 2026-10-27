import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Macorn

/// Macorn で開けるファイルの種類（「このアプリケーションで開く」への申告と、既定のアプリの切り替えの対象）
struct DefaultFileAppsTests {
    /// Info.plist で申告している種類
    private var declaredTypes: [UTType] {
        let documents = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        return documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }.compactMap(UTType.init)
    }

    @Test func everyKindIsDeclared() {
        let declared = declaredTypes
        for kind in PreviewFileKind.allCases {
            for identifier in kind.typeIdentifiers {
                let type = UTType(identifier)
                #expect(type != nil, "\(identifier) が macOS の種類にない")
                #expect(declared.contains { type?.conforms(to: $0) == true }, "\(identifier) を Info.plist で申告していない")
            }
        }
    }

    @Test func foldersAreStillDeclared() {
        #expect(declaredTypes.contains(.folder))
    }

    @Test func kindsArePreviewable() {
        // 既定にできる種類は、どれもプレビューで見られるもの
        let samples = ["a.pdf", "a.md", "a.html", "a.png", "a.jpg", "a.mp4", "a.mov", "a.mp3", "a.m4a"]
        for name in samples {
            #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/tmp/\(name)")) != nil, "\(name) をプレビューできない")
        }
    }
}
