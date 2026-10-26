import Foundation

enum DebugFlags {
    /// Debug ビルドの自動操作（MACORN_DEBUG_STEPS）で動いているか。
    /// 自動操作中は、利用者のキー入力を奪わないようにウインドウをキーにしない。
    static var isAutomating: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MACORN_DEBUG_STEPS"] != nil
        #else
        false
        #endif
    }
}
