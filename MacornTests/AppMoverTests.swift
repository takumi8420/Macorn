import Foundation
import Testing
@testable import Macorn

/// 「アプリケーション」フォルダへ移すかの判断と、移す処理
struct AppMoverTests {
    private let home = URL(fileURLWithPath: "/Users/someone")
    private let destination = URL(fileURLWithPath: "/Applications")

    @Test func applicationsFoldersNeedNoMove() {
        #expect(AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Macorn.app"), destination: destination, home: home))
        #expect(AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Tools/Macorn.app"), destination: destination, home: home))
        #expect(AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Users/someone/Applications/Macorn.app"), destination: destination, home: home))
    }

    @Test func otherPlacesAreOffered() {
        #expect(!AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Volumes/Macorn/Macorn.app"), destination: destination, home: home))
        #expect(!AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Users/someone/Downloads/Macorn.app"), destination: destination, home: home))
        // 名前が似ているだけのフォルダは「アプリケーション」ではない
        #expect(!AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/ApplicationsOld/Macorn.app"), destination: destination, home: home))
    }

    @Test func translocatedPathIsDetected() {
        #expect(AppMover.isTranslocated(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Macorn.app")))
        #expect(!AppMover.isTranslocated(URL(fileURLWithPath: "/Volumes/Macorn/Macorn.app")))
    }

    @Test func bootVolumeIsNotDiskImage() {
        #expect(AppMover.diskImageVolume(of: URL(fileURLWithPath: NSTemporaryDirectory())) == nil)
    }

    private func makeFakeApp() throws -> (root: URL, app: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("macorn-mover-\(UUID().uuidString)")
        let app = root.appendingPathComponent("from/Macorn.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "x".write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        return (root, app)
    }

    @Test func copiesWhenKeepingOriginal() throws {
        let (root, app) = try makeFakeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try AppMover.install(app, into: root.appendingPathComponent("Apps"), keepOriginal: true)
        #expect(installed.path == root.appendingPathComponent("Apps/Macorn.app").path)
        #expect(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func movesOtherwise() throws {
        let (root, app) = try makeFakeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try AppMover.install(app, into: root.appendingPathComponent("Apps"), keepOriginal: false)
        #expect(FileManager.default.fileExists(atPath: installed.path))
        #expect(!FileManager.default.fileExists(atPath: app.path))
    }
}
