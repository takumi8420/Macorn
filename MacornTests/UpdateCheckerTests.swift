import Foundation
import Testing
@testable import Macorn

/// 新しい版の確認（LP の version.json と今の版を比べる）
struct UpdateCheckerTests {
    @Test func comparesVersionsNumerically() {
        #expect(UpdateChecker.isNewer("0.3.0", than: "0.2.0"))
        #expect(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        #expect(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        #expect(UpdateChecker.isNewer("0.2.1", than: "0.2"))
        #expect(!UpdateChecker.isNewer("0.2.0", than: "0.2.0"))
        #expect(!UpdateChecker.isNewer("0.2", than: "0.2.0"))
        #expect(!UpdateChecker.isNewer("0.1.9", than: "0.2.0"))
    }

    private func feed(_ json: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("macorn-version-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let sample = #"{"version": "0.3.0", "build": 3, "download": "https://macorn.vercel.app/download/Macorn.dmg", "page": "https://macorn.vercel.app/#get"}"#

    @Test func reportsNewerVersion() async throws {
        let url = try feed(sample)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await UpdateChecker.fetch(from: url, current: "0.2.0")
        guard case .available(let info) = result else {
            Issue.record("新しい版として扱われなかった: \(result)")
            return
        }
        #expect(info.version == "0.3.0")
        #expect(info.download.absoluteString == "https://macorn.vercel.app/download/Macorn.dmg")
    }

    @Test func sameVersionIsUpToDate() async throws {
        let url = try feed(sample)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await UpdateChecker.fetch(from: url, current: "0.3.0") == .upToDate)
        #expect(await UpdateChecker.fetch(from: url, current: "0.4.0") == .upToDate)
    }

    @Test func brokenFeedFails() async throws {
        let url = try feed("<html>not json</html>")
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .failed = await UpdateChecker.fetch(from: url, current: "0.2.0") else {
            Issue.record("読めない情報で失敗にならなかった")
            return
        }
    }

    @Test func siteFeedMatchesAppVersion() throws {
        // LP に置いている version.json は、アプリのバージョンとそろっている（release.sh --publish で書き直す）
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("site/version.json"))
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        #expect(!UpdateChecker.isNewer(info.version, than: UpdateChecker.currentVersion))
    }
}
