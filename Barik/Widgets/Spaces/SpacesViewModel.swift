import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    private var provider: AnySpacesProvider?
    private var fallbackTimer: Timer?

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
            startSignalMonitoring()
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
            startFallbackMonitoring()
        } else {
            provider = nil
        }

        // Initial load
        loadSpaces()
    }

    deinit {
        stopMonitoring()
    }

    /// Start event-driven monitoring using yabai signals (via Darwin notifications)
    private func startSignalMonitoring() {
        // Use Darwin notifications (CFNotificationCenter) for low-latency IPC
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, name, _, _ in
                guard let observer = observer else { return }
                let viewModel = Unmanaged<SpacesViewModel>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    viewModel.loadSpaces()
                }
            },
            "com.barik.space_changed" as CFString,
            nil,
            .deliverImmediately
        )

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, name, _, _ in
                guard let observer = observer else { return }
                let viewModel = Unmanaged<SpacesViewModel>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    viewModel.loadSpaces()
                }
            },
            "com.barik.window_changed" as CFString,
            nil,
            .deliverImmediately
        )

        // Fallback polling every 0.5s for safety (still 5x better than original 0.1s)
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.loadSpaces()
        }
    }

    /// Start fallback polling for non-yabai setups
    private func startFallbackMonitoring() {
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.loadSpaces()
        }
    }

    private func stopMonitoring() {
        // Remove Darwin notification observers
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, nil, nil)

        // Stop fallback timer
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func loadSpaces() {
        DispatchQueue.global(qos: .background).async {
            guard let provider = self.provider,
                let spaces = provider.getSpacesWithWindows()
            else {
                DispatchQueue.main.async {
                    self.spaces = []
                }
                return
            }
            let sortedSpaces = spaces.sorted { $0.id < $1.id }
            DispatchQueue.main.async {
                self.spaces = sortedSpaces
            }
        }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
