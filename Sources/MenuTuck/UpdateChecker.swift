import AppKit

/// Manual "Check for Updates…": one GitHub API call, only when the user asks.
enum UpdateChecker {
    private static let latestURL = URL(string: "https://api.github.com/repos/acchuang/MenuTuck/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/acchuang/MenuTuck/releases")!
    @MainActor private static var isChecking = false

    /// "v0.1.10" is newer than "0.1.9". Dotted numeric compare, no prerelease handling.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        let strip = { (s: String) in s.hasPrefix("v") ? String(s.dropFirst()) : s }
        return strip(tag).compare(strip(current), options: .numeric) == .orderedDescending
    }

    static func run() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        Task { @MainActor in
            guard !isChecking else { return }
            isChecking = true
            defer { isChecking = false }

            var request = URLRequest(url: latestURL, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let result = try? await URLSession.shared.data(for: request)
            let httpOK = (result?.1 as? HTTPURLResponse)?.statusCode == 200
            let json = httpOK
                ? result.flatMap { try? JSONSerialization.jsonObject(with: $0.0) as? [String: Any] }
                : nil
            let alert = NSAlert()
            var pageURL: URL?
            if let tag = json?["tag_name"] as? String {
                if isNewer(tag, than: current) {
                    alert.messageText = "\(tag) is available"
                    alert.informativeText = "You have v\(current)."
                    let candidate = (json?["html_url"] as? String).flatMap(URL.init(string:))
                    pageURL = (candidate?.scheme == "https") ? candidate : releasesPageURL
                    alert.addButton(withTitle: "Open Release Page")
                    alert.addButton(withTitle: "Later")
                } else {
                    alert.messageText = "You're up to date (v\(current))"
                }
            } else {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Are you offline? Try again, or see the Releases page on GitHub."
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let pageURL {
                NSWorkspace.shared.open(pageURL)
            }
        }
    }
}
