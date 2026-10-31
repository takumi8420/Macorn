import Foundation
import Testing
@testable import Macorn

/// 自動更新で入れ替える前の確かめ（ほかのアプリ・版違い・配布用の署名がないものは入れ替えない）
struct UpdateInstallerTests {
    @Test func rejectsAnotherApp() {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        #expect(throws: UpdateInstaller.Failure.self) {
            try UpdateInstaller.verify(calculator, team: "Q9Q29NW29B", version: "1.0")
        }
    }

    @Test func rejectsOtherVersion() {
        #expect(throws: UpdateInstaller.Failure.self) {
            try UpdateInstaller.verify(Bundle.main.bundleURL, team: "Q9Q29NW29B", version: "999.0.0")
        }
    }

    /// 開発用のビルドは簡易署名なので、Developer ID の条件を満たさない
    @Test func rejectsAdHocSignature() {
        let version = UpdateChecker.currentVersion
        do {
            try UpdateInstaller.verify(Bundle.main.bundleURL, team: "Q9Q29NW29B", version: version)
            Issue.record("簡易署名のビルドを受け入れてしまった")
        } catch let failure as UpdateInstaller.Failure {
            guard case .untrusted = failure else { Issue.record("想定と違う失敗: \(failure)"); return }
        } catch {
            Issue.record("想定と違う失敗: \(error)")
        }
    }
}
