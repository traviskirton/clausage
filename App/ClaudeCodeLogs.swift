import AppKit

/// Access to Claude Code's local session logs (~/.claude/projects). The app is sandboxed, so the user grants access to
/// the folder once; the scan runs on this Mac and nothing leaves it.
enum ClaudeCodeLogs {
    private static let bookmarkKey = "claudeDirBookmark"

    static var hasAccess: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// The last breakdown, so switching panes doesn't rescan.
    @MainActor static var lastResult: ContributorsScan.Result?
    /// Debug gallery: draw the pane as if access were granted.
    nonisolated(unsafe) static var previewAccess = false

    private static var realHome: String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    @MainActor
    static func chooseFolder() -> Bool {
        AppActivation.push()
        defer { AppActivation.pop() }
        let panel = NSOpenPanel()
        panel.message = "Choose your .claude folder so Clausage can read Claude Code's local session logs."
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: realHome + "/.claude")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return true
    }

    @MainActor
    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        lastResult = nil
    }

    /// "What's contributing to your limits usage?" for the last 24 hours and 7 days, scanned off the main thread.
    @MainActor
    static func contributors() async -> ContributorsScan.Result? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        let result = await Task.detached(priority: .utility) { () -> ContributorsScan.Result? in
            var stale = false
            guard let root = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
                  root.startAccessingSecurityScopedResource() else { return nil }
            defer { root.stopAccessingSecurityScopedResource() }
            return ContributorsScan.scan(claudeDir: root)
        }.value
        if let result { lastResult = result }
        return result
    }
}
