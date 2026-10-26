import AppKit

/// コピー・移動・ゴミ箱・削除・作成・名前変更をまとめて受け持つ。
/// 取り消し（⌘Z）はアプリ全体で1つの履歴を使う（Finder と同じ）。
final class FileOperationManager {
    static let shared = FileOperationManager()

    let undoManager = UndoManager()

    nonisolated enum TransferMode: Sendable {
        case copy, move

        var verb: String { self == .copy ? "コピー" : "移動" }
    }

    enum ConflictChoice {
        case keepBoth, replace, skip, stop
    }

    #if DEBUG
    /// 自動テスト用: ダイアログを出さずに答えを決める。
    var debugConflictChoice: ConflictChoice?
    var debugConfirmDeletion: Bool?
    #endif

    private struct TransferRecord {
        var mode: TransferMode
        var destinationFolder: URL
        var pairs: [(source: URL, destination: URL)] = []
        /// 「置き換え」でゴミ箱に入れた既存の項目（取り消すときに戻す）
        var replaced: [(original: URL, trashed: URL)] = []
    }

    // MARK: - コピー・移動

    /// 戻り値はコピー・移動後の場所。
    @discardableResult
    func transfer(_ sources: [URL], to folder: URL, mode: TransferMode, window: NSWindow?) async -> [URL] {
        let sources = sources.map(\.standardizedFileURL)
        let folder = folder.standardizedFileURL
        guard !sources.isEmpty else { return [] }

        // フォルダを自分自身の中へは入れられない
        if let source = sources.first(where: { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }) {
            await showMessage("「\(source.lastPathComponent)」をその中に\(mode.verb)することはできません。", window: window)
            return []
        }

        let operation = FileOperation(kind: mode == .copy ? .copy : .move, itemCount: sources.count)
        OperationsPanelController.shared.start(operation)
        defer { OperationsPanelController.shared.finish(operation) }

        let sameVolume = await Task.detached {
            sources.allSatisfy { FileTransfer.isSameVolume($0, folder) }
        }.value
        if mode == .copy || !sameVolume {
            operation.totalBytes = await Task.detached { FileTransfer.totalSize(of: sources) }.value
        }

        let poller = Task {
            while !Task.isCancelled {
                operation.syncFromProgress()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { poller.cancel() }

        var record = TransferRecord(mode: mode, destinationFolder: folder)
        var rememberedChoice: ConflictChoice?

        items: for (index, source) in sources.enumerated() {
            if operation.progress.isCancelled { break }
            let isDirectory = FileTransfer.isDirectory(source)
            var target = folder.appendingPathComponent(source.lastPathComponent)

            if source.deletingLastPathComponent().path == folder.path {
                // 同じフォルダへの移動は何もしない。コピーは「〜 のコピー」を作る
                if mode == .move { continue }
                target = FileNaming.uniqueURL(for: target, isDirectory: isDirectory, style: .copy)
            } else if FileNaming.itemExists(target) {
                let choice: ConflictChoice
                if let rememberedChoice {
                    choice = rememberedChoice
                } else {
                    let answer = await askConflict(name: target.lastPathComponent, remaining: sources.count - index, window: window)
                    choice = answer.choice
                    if answer.applyToAll { rememberedChoice = choice }
                }

                switch choice {
                case .stop:
                    break items
                case .skip:
                    continue items
                case .keepBoth:
                    target = FileNaming.uniqueURL(for: target, isDirectory: isDirectory, style: .numbered)
                case .replace:
                    if source.path.hasPrefix(target.path + "/") {
                        await showMessage("「\(target.lastPathComponent)」は\(mode.verb)元を含んでいるため置き換えできません。", window: window)
                        continue items
                    }
                    do {
                        let trashed = try await recycle([target])
                        if let trashedURL = trashed.first?.trashed {
                            record.replaced.append((target, trashedURL))
                        }
                    } catch {
                        await showError(error, window: window)
                        continue items
                    }
                }
            }

            do {
                operation.progress.begin(name: source.lastPathComponent)
                let progress = operation.progress
                let finalTarget = target
                try await Task.detached(priority: .userInitiated) {
                    switch mode {
                    case .copy:
                        try FileTransfer.copyItem(at: source, to: finalTarget, progress: progress)
                    case .move:
                        try FileTransfer.moveItem(at: source, to: finalTarget, sameVolume: sameVolume, progress: progress)
                    }
                }.value
                record.pairs.append((source, target))
                // 移動した項目のタグは、移動先に付け替える（コピーにはタグを付けない）
                if mode == .move { TagStore.shared.itemMoved(from: source, to: target) }
            } catch {
                if operation.progress.isCancelled || error is CancellationError { break items }
                await showError(error, window: window)
            }
        }

        operation.syncFromProgress()
        if !record.pairs.isEmpty || !record.replaced.isEmpty {
            registerUndo(for: record)
        }
        return record.pairs.map(\.destination)
    }

    private func registerUndo(for record: TransferRecord) {
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoTransfer(record)
        }
        undoManager.setActionName(record.mode.verb)
    }

    private func undoTransfer(_ record: TransferRecord) {
        // やり直し（⌘⇧Z）は同じ項目をもう一度コピー・移動する
        undoManager.registerUndo(withTarget: self) { manager in
            Task {
                await manager.transfer(record.pairs.map(\.source), to: record.destinationFolder, mode: record.mode, window: NSApp.keyWindow)
            }
        }
        undoManager.setActionName(record.mode.verb)

        Task {
            switch record.mode {
            case .copy:
                // 作ったコピーはゴミ箱へ（完全には消さない）
                _ = try? await recycle(record.pairs.map(\.destination))
            case .move:
                for pair in record.pairs.reversed() {
                    await moveBack(from: pair.destination, to: pair.source)
                }
            }
            for item in record.replaced {
                await moveBack(from: item.trashed, to: item.original)
            }
        }
    }

    private func moveBack(from current: URL, to original: URL) async {
        do {
            let sameVolume = FileTransfer.isSameVolume(current, original.deletingLastPathComponent())
            try await Task.detached {
                try FileTransfer.moveItem(at: current, to: original, sameVolume: sameVolume, progress: TransferProgress())
            }.value
            TagStore.shared.itemMoved(from: current, to: original)
        } catch {
            await showError(error, window: NSApp.keyWindow)
        }
    }

    // MARK: - ゴミ箱・削除

    func moveToTrash(_ urls: [URL], window: NSWindow?) async {
        guard !urls.isEmpty else { return }
        do {
            let pairs = try await recycle(urls)
            guard !pairs.isEmpty else { return }
            undoManager.registerUndo(withTarget: self) { manager in
                manager.undoTrash(pairs)
            }
            undoManager.setActionName("ゴミ箱に入れる")
        } catch {
            await showError(error, window: window)
        }
    }

    private func undoTrash(_ pairs: [(original: URL, trashed: URL)]) {
        undoManager.registerUndo(withTarget: self) { manager in
            Task { await manager.moveToTrash(pairs.map(\.original), window: NSApp.keyWindow) }
        }
        undoManager.setActionName("ゴミ箱に入れる")
        Task {
            for pair in pairs {
                await moveBack(from: pair.trashed, to: pair.original)
            }
        }
    }

    func recycle(_ urls: [URL]) async throws -> [(original: URL, trashed: URL)] {
        let result = try await NSWorkspace.shared.recycle(urls)
        return urls.compactMap { url in
            let match = result.first { $0.key.standardizedFileURL.path == url.standardizedFileURL.path }
            return match.map { (url, $0.value) }
        }
    }

    /// すぐに削除（ゴミ箱を使わない）。取り消せないので必ず確認する。
    func deletePermanently(_ urls: [URL], window: NSWindow?) async {
        guard !urls.isEmpty, await confirmDeletion(of: urls, window: window) else { return }
        let operation = FileOperation(kind: .delete, itemCount: urls.count)
        OperationsPanelController.shared.start(operation)
        defer { OperationsPanelController.shared.finish(operation) }

        for url in urls {
            do {
                try await Task.detached { try FileManager.default.removeItem(at: url) }.value
            } catch {
                await showError(error, window: window)
                break
            }
        }
    }

    private func confirmDeletion(of urls: [URL], window: NSWindow?) async -> Bool {
        #if DEBUG
        if let debugConfirmDeletion { return debugConfirmDeletion }
        #endif
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = urls.count == 1
            ? "「\(urls[0].lastPathComponent)」をすぐに削除しますか？"
            : "\(urls.count) 項目をすぐに削除しますか？"
        alert.informativeText = "ゴミ箱を使わずに削除します。この操作は取り消せません。"
        let delete = alert.addButton(withTitle: "削除")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "キャンセル")
        cancel.keyEquivalent = "\r"
        return await present(alert, window: window) == .alertFirstButtonReturn
    }

    // MARK: - 新規作成

    func createFolder(in folder: URL, window: NSWindow?) async -> URL? {
        let url = FileNaming.uniqueURL(for: folder.appendingPathComponent(FileNaming.newFolderName), isDirectory: true, style: .numbered)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            registerCreationUndo(url, isDirectory: true)
            return url
        } catch {
            await showError(error, window: window)
            return nil
        }
    }

    func createFile(in folder: URL, window: NSWindow?) async -> URL? {
        let url = FileNaming.uniqueURL(for: folder.appendingPathComponent(FileNaming.newFileName), isDirectory: false, style: .numbered)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            await showMessage("「\(url.lastPathComponent)」を作成できませんでした。", window: window)
            return nil
        }
        registerCreationUndo(url, isDirectory: false)
        return url
    }

    private func registerCreationUndo(_ url: URL, isDirectory: Bool) {
        let name = isDirectory ? "新規フォルダ" : "新規ファイル"
        undoManager.registerUndo(withTarget: self) { manager in
            // やり直しでは同じ名前で作り直す
            manager.undoManager.registerUndo(withTarget: manager) { manager in
                if isDirectory {
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: Data())
                }
                manager.registerCreationUndo(url, isDirectory: isDirectory)
            }
            manager.undoManager.setActionName(name)
            Task { _ = try? await manager.recycle([url]) }
        }
        undoManager.setActionName(name)
    }

    // MARK: - 名前の変更

    /// 戻り値は変更後の場所。変更できなければ nil。
    func rename(_ url: URL, to newName: String, window: NSWindow?) async -> URL? {
        if let message = FileNaming.validationError(for: newName) {
            await showMessage(message, window: window)
            return nil
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard target.path != url.path else { return url }

        // 大文字・小文字だけの変更は同じファイルを指すので、重複扱いにしない
        if FileNaming.itemExists(target), !FileTransfer.isSameFile(url, target) {
            await showMessage("「\(newName)」という名前はすでに使われています。別の名前を選んでください。", window: window)
            return nil
        }
        do {
            try performRename(from: url, to: target)
            return target
        } catch {
            await showError(error, window: window)
            return nil
        }
    }

    private func performRename(from source: URL, to target: URL) throws {
        // rename(2) は同じ名前のものがあると上書きしてしまうので、呼ぶ前に必ず確認しておく
        guard Darwin.rename(source.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        TagStore.shared.itemMoved(from: source, to: target)
        undoManager.registerUndo(withTarget: self) { manager in
            do {
                try manager.performRename(from: target, to: source)
            } catch {
                Task { await manager.showError(error, window: NSApp.keyWindow) }
            }
        }
        undoManager.setActionName("名前の変更")
    }

    // MARK: - ダイアログ

    /// F5 / F6 の確認。コピー先をはっきり見せ、Enter で実行、Esc で中止する。
    func confirmTransfer(count: Int, destination: URL, mode: TransferMode, window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(count) 項目を\(mode.verb)します"
        alert.informativeText = "\(mode.verb)先: \(PathCompletion.abbreviate(destination.path))"
        alert.addButton(withTitle: mode.verb)
        alert.addButton(withTitle: "キャンセル")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "今後は確認しない"
        let confirmed = await present(alert, window: window) == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            Preferences.confirmPaneTransfer = false
        }
        return confirmed
    }

    private func askConflict(name: String, remaining: Int, window: NSWindow?) async -> (choice: ConflictChoice, applyToAll: Bool) {
        #if DEBUG
        if let debugConflictChoice { return (debugConflictChoice, true) }
        #endif
        let alert = NSAlert()
        alert.messageText = "「\(name)」という名前の項目がすでにこの場所にあります。"
        alert.informativeText = "置き換えると、元の項目はゴミ箱に移動します。"
        alert.addButton(withTitle: "両方残す")
        alert.addButton(withTitle: "置き換える")
        alert.addButton(withTitle: "スキップ")
        let stop = alert.addButton(withTitle: "中止")
        stop.keyEquivalent = "\u{1b}"
        if remaining > 1 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "残りのすべてに適用"
        }
        let response = await present(alert, window: window)
        let choice: ConflictChoice = switch response {
        case .alertFirstButtonReturn: .keepBoth
        case .alertSecondButtonReturn: .replace
        case .alertThirdButtonReturn: .skip
        default: .stop
        }
        return (choice, alert.suppressionButton?.state == .on)
    }

    func showMessage(_ message: String, window: NSWindow?) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        _ = await present(alert, window: window)
    }

    func showError(_ error: any Error, window: NSWindow?) async {
        #if DEBUG
        print("[debug] error \(error.localizedDescription)")
        #endif
        _ = await present(NSAlert(error: error), window: window)
    }

    private func present(_ alert: NSAlert, window: NSWindow?) async -> NSApplication.ModalResponse {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MACORN_DEBUG_STEPS"] != nil {
            print("[debug] alert \(alert.messageText)")
            return .alertFirstButtonReturn
        }
        #endif
        if let window, window.isVisible, window.attachedSheet == nil {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }
}
