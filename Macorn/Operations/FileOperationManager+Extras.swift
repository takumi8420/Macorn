import AppKit

/// 一括での名前の変更（F-13）、シンボリックリンク（F-10）、圧縮・展開（F-11）。
extension FileOperationManager {
    // MARK: - 一括での名前の変更

    /// 戻り値は変更後の場所。名前を入れ替えるような変更（a→b, b→a）もできるよう、
    /// いったん一時的な名前にしてから最終的な名前にする。
    @discardableResult
    func bulkRename(_ changes: [(url: URL, newName: String)], window: NSWindow?) async -> [URL] {
        let changes = changes.filter { $0.url.lastPathComponent != $0.newName }
        guard !changes.isEmpty else { return [] }

        var temporary: [(url: URL, temp: URL, final: URL)] = []
        do {
            for (index, change) in changes.enumerated() {
                let temp = change.url.deletingLastPathComponent().appendingPathComponent(".macorn-rename-\(UUID().uuidString)-\(index)")
                try FileManager.default.moveItem(at: change.url, to: temp)
                temporary.append((change.url, temp, change.url.deletingLastPathComponent().appendingPathComponent(change.newName)))
            }
            for item in temporary {
                guard !FileNaming.itemExists(item.final) else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: item.final.path])
                }
                try FileManager.default.moveItem(at: item.temp, to: item.final)
            }
        } catch {
            // 途中で失敗したら、一時的な名前のものを元の名前に戻す
            for item in temporary where FileNaming.itemExists(item.temp) {
                try? FileManager.default.moveItem(at: item.temp, to: item.url)
            }
            await showError(error, window: window)
            return []
        }

        let results = temporary.map(\.final)
        for item in temporary { TagStore.shared.itemMoved(from: item.url, to: item.final) }
        let inverse = temporary.map { (url: $0.final, newName: $0.url.lastPathComponent) }
        undoManager.registerUndo(withTarget: self) { manager in
            Task { await manager.bulkRename(inverse, window: NSApp.keyWindow) }
        }
        undoManager.setActionName("名前の変更")
        return results
    }

    // MARK: - シンボリックリンク

    /// 選んだ項目へのシンボリックリンクを、同じフォルダに「〜 のリンク」として作る。
    func makeSymbolicLinks(to urls: [URL], window: NSWindow?) async -> [URL] {
        var created: [URL] = []
        for url in urls {
            let isDirectory = FileTransfer.isDirectory(url)
            let (base, ext) = FileNaming.split(url.lastPathComponent, isDirectory: isDirectory)
            let name = ext.isEmpty ? "\(base) のリンク" : "\(base) のリンク.\(ext)"
            let link = FileNaming.uniqueURL(
                for: url.deletingLastPathComponent().appendingPathComponent(name),
                isDirectory: isDirectory, style: .numbered
            )
            do {
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
                created.append(link)
            } catch {
                await showError(error, window: window)
            }
        }
        registerTrashUndo(for: created, name: "シンボリックリンクの作成")
        return created
    }

    // MARK: - 圧縮・展開

    /// zip に圧縮する。1つなら「名前.zip」、複数なら「アーカイブ.zip」。
    func compress(_ urls: [URL], window: NSWindow?) async -> URL? {
        guard let first = urls.first else { return nil }
        let folder = first.deletingLastPathComponent()
        let name = urls.count == 1 ? first.lastPathComponent + ".zip" : "アーカイブ.zip"
        let archive = FileNaming.uniqueURL(for: folder.appendingPathComponent(name), isDirectory: false, style: .numbered)

        let operation = FileOperation(kind: .compress, itemCount: urls.count)
        OperationsPanelController.shared.start(operation)
        defer { OperationsPanelController.shared.finish(operation) }

        let succeeded: Bool
        if urls.count == 1 {
            // ditto は Finder の「圧縮」と同じ形式（拡張属性などを含む）で作る
            succeeded = await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, archive.path])
        } else {
            let names = urls.map { $0.deletingLastPathComponent().path == folder.path ? $0.lastPathComponent : $0.path }
            succeeded = await run("/usr/bin/zip", ["-r", "-y", "-q", archive.path] + names, directory: folder)
        }
        guard succeeded else {
            try? FileManager.default.removeItem(at: archive)
            await showMessage("圧縮できませんでした。", window: window)
            return nil
        }
        registerTrashUndo(for: [archive], name: "圧縮")
        return archive
    }

    /// zip を同じフォルダに展開する。中身が1つだけならそれをそのまま置く（Finder と同じ）。
    func expand(_ archive: URL, window: NSWindow?) async -> URL? {
        let folder = archive.deletingLastPathComponent()
        let base = archive.deletingPathExtension().lastPathComponent
        // いったん隠しフォルダに展開してから、置き場所を決める（名前の重なりを避けるため）
        let staging = folder.appendingPathComponent(".macorn-expand-\(UUID().uuidString)")

        let operation = FileOperation(kind: .expand, itemCount: 1)
        OperationsPanelController.shared.start(operation)
        defer { OperationsPanelController.shared.finish(operation) }

        guard await run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path]) else {
            try? FileManager.default.removeItem(at: staging)
            await showMessage("「\(archive.lastPathComponent)」を展開できませんでした。", window: window)
            return nil
        }
        try? FileManager.default.removeItem(at: staging.appendingPathComponent("__MACOSX"))
        let contents = ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? [])
            .filter { $0 != ".DS_Store" }

        let source: URL
        let target: URL
        if contents.count == 1 {
            source = staging.appendingPathComponent(contents[0])
            target = FileNaming.uniqueURL(
                for: folder.appendingPathComponent(contents[0]),
                isDirectory: FileTransfer.isDirectory(source), style: .numbered
            )
        } else {
            source = staging
            target = FileNaming.uniqueURL(for: folder.appendingPathComponent(base), isDirectory: true, style: .numbered)
        }
        do {
            try FileManager.default.moveItem(at: source, to: target)
            try? FileManager.default.removeItem(at: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            await showError(error, window: window)
            return nil
        }
        registerTrashUndo(for: [target], name: "展開")
        return target
    }

    /// 作ったものを取り消すときはゴミ箱へ入れる。やり直しはゴミ箱から戻す。
    private func registerTrashUndo(for urls: [URL], name: String) {
        guard !urls.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { manager in
            Task {
                guard let pairs = try? await manager.recycle(urls) else { return }
                manager.undoManager.registerUndo(withTarget: manager) { manager in
                    Task {
                        for pair in pairs {
                            try? FileManager.default.moveItem(at: pair.trashed, to: pair.original)
                        }
                        manager.registerTrashUndo(for: urls, name: name)
                    }
                }
                manager.undoManager.setActionName(name)
            }
        }
        undoManager.setActionName(name)
    }

    private func run(_ executable: String, _ arguments: [String], directory: URL? = nil) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = directory }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return false
            }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }
}
