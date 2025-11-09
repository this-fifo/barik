import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    private var provider: AnySpacesProvider?
    private var reloadObserver: NSObjectProtocol?
    private let loadQueue = DispatchQueue(
        label: "io.barik.spaces.reload", qos: .background)
    private var isLoading = false
    private var pendingReload = false
    private var cachedSpaces: [AnySpace] = []
    private var focusTimer: Timer?

    init() {
        let distributedCenter = DistributedNotificationCenter.default()
        reloadObserver = distributedCenter.addObserver(
            forName: .barikReloadSpaces,
            object: nil,
            queue: .main,
            using: { [weak self] notification in
                let providedFocusId =
                    notification.userInfo?["focusedSpaceId"] as? String
                let providedWindowId =
                    (notification.userInfo?["focusedWindowId"] as? String)
                    .flatMap(Int.init)
                self?.loadSpaces(
                    triggeredByEvent: true,
                    providedFocusId: providedFocusId,
                    providedWindowId: providedWindowId)
            })
        loadSpaces()
        startFocusPolling()
    }

    deinit {
        if let observer = reloadObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        focusTimer?.invalidate()
    }

    private func loadSpaces(
        triggeredByEvent: Bool = false, providedFocusId: String? = nil,
        providedWindowId: Int? = nil
    ) {
        loadQueue.async { [weak self] in
            guard let self else { return }
            self.ensureProvider()
            if triggeredByEvent {
                self.applyQuickFocusUpdateOnQueue(
                    providedFocusId: providedFocusId,
                    providedWindowId: providedWindowId)
            }
            if self.isLoading {
                self.pendingReload = true
                return
            }
            self.isLoading = true
            self.pendingReload = false
            defer {
                self.isLoading = false
                if self.pendingReload {
                    self.loadSpaces()
                }
            }
            guard let provider = self.provider,
                let spaces = provider.getSpacesWithWindows()
            else {
                self.cachedSpaces = []
                DispatchQueue.main.async {
                    self.spaces = []
                }
                return
            }
            let sortedSpaces = spaces.sorted {
                let lhsInt = Int($0.id) ?? Int.max
                let rhsInt = Int($1.id) ?? Int.max
                // sort for numbers
                if lhsInt != rhsInt { return lhsInt < rhsInt }
                // sort by alphabet
                return $0.id < $1.id
            }
            self.cachedSpaces = sortedSpaces
            DispatchQueue.main.async {
                self.spaces = sortedSpaces
            }
        }
    }

    private func ensureProvider() {
        if provider != nil { return }
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        }
    }

    private func applyQuickFocusUpdateOnQueue(
        providedFocusId: String?, providedWindowId: Int?
    ) {
        guard !cachedSpaces.isEmpty else {
            return
        }
        let focusId = providedFocusId ?? provider?.getFocusedSpaceId()
        let windowId = providedWindowId
        if focusId == nil && windowId == nil { return }
        var changed = false
        let updatedSpaces = cachedSpaces.map { space -> AnySpace in
            var updatedWindows = space.windows
            if let windowId {
                updatedWindows = space.windows.map { window in
                    let newFocus = (window.id == windowId)
                    if window.isFocused != newFocus { changed = true }
                    return window.withFocus(newFocus)
                }
            }
            var updatedSpace = space
            if let focusId {
                let newFocus = (space.id == focusId)
                if space.isFocused != newFocus {
                    changed = true
                    updatedSpace = space.withFocus(newFocus)
                }
            }
            if updatedWindows != space.windows {
                changed = true
                updatedSpace = AnySpace(
                    id: updatedSpace.id,
                    isFocused: updatedSpace.isFocused,
                    windows: updatedWindows)
            }
            return updatedSpace
        }
        if changed {
            cachedSpaces = updatedSpaces
            let snapshot = updatedSpaces
            DispatchQueue.main.async {
                self.spaces = snapshot
            }
        }
    }

    private func startFocusPolling() {
        // Poll focused window every 0.5 seconds
        focusTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.pollFocusedWindow()
        }
    }

    private func pollFocusedWindow() {
        loadQueue.async { [weak self] in
            guard let self, let provider = self.provider else { return }
            guard let windowId = provider.getFocusedWindowId() else { return }

            // Update focus using the quick update mechanism
            self.applyQuickFocusUpdateOnQueue(
                providedFocusId: nil,
                providedWindowId: windowId)
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
