import AppKit
import SwiftUI

/// 一括での名前の変更・情報を見る・圧縮と展開・シンボリックリンク（M6）。
extension FileBrowserViewController {
    @objc func bulkRename(_ sender: Any?) {
        let nodes = selectedNodes
        guard !nodes.isEmpty, let window = view.window else { return }
        let items = nodes.map { (url: $0.url, isDirectory: $0.entry.isFolder) }

        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520), styleMask: [.titled], backing: .buffered, defer: true)
        sheet.contentViewController = NSHostingController(rootView: BulkRenameView(
            items: items,
            onCancel: { [weak window, weak sheet] in
                guard let sheet else { return }
                window?.endSheet(sheet)
            },
            onApply: { [weak self, weak window, weak sheet] changes in
                guard let self, let sheet else { return }
                window?.endSheet(sheet)
                Task {
                    let results = await FileOperationManager.shared.bulkRename(changes, window: window)
                    refreshAfterChange(selecting: results)
                }
            }
        ))
        window.beginSheet(sheet)
        bulkRenameSheet = sheet
    }

    @objc func showInfo(_ sender: Any?) {
        InfoPanels.show(selectedURLs.isEmpty ? [state.currentURL] : selectedURLs)
    }

    @objc func makeSymbolicLink(_ sender: Any?) {
        let urls = selectedURLs
        Task {
            let links = await FileOperationManager.shared.makeSymbolicLinks(to: urls, window: view.window)
            refreshAfterChange(selecting: links)
        }
    }

    @objc func compress(_ sender: Any?) {
        let urls = selectedURLs
        Task {
            guard let archive = await FileOperationManager.shared.compress(urls, window: view.window) else { return }
            refreshAfterChange(selecting: [archive])
        }
    }

    @objc func expandArchive(_ sender: Any?) {
        let archives = selectedURLs.filter(Self.isZip)
        Task {
            var results: [URL] = []
            for archive in archives {
                if let result = await FileOperationManager.shared.expand(archive, window: view.window) {
                    results.append(result)
                }
            }
            refreshAfterChange(selecting: results)
        }
    }

    static func isZip(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    func validateExtrasMenuItem(_ item: NSMenuItem) -> Bool? {
        let editing = view.window?.firstResponder is NSText
        switch item.action {
        case #selector(bulkRename(_:)), #selector(makeSymbolicLink(_:)), #selector(compress(_:)):
            return !editing && !selectedNodes.isEmpty
        case #selector(expandArchive(_:)):
            return !editing && selectedURLs.contains(where: Self.isZip)
        case #selector(showInfo(_:)):
            return !editing
        default:
            return nil
        }
    }
}
