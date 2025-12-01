import AppKit
import SwiftUI

/// Manages display detection and provides information about the current screen
final class DisplayManager: ObservableObject {
    static let shared = DisplayManager()

    @Published private(set) var isBuiltinDisplay: Bool = false
    @Published private(set) var hasNotch: Bool = false
    /// Minimum width the spacer needs to clear the notch area
    @Published private(set) var notchSpacerWidth: CGFloat = 0

    private init() {
        // Delay initial update to ensure screen is available
        DispatchQueue.main.async {
            self.updateDisplayInfo()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange() {
        DispatchQueue.main.async {
            self.updateDisplayInfo()
        }
    }

    private func updateDisplayInfo() {
        guard let screen = NSScreen.main else {
            isBuiltinDisplay = false
            hasNotch = false
            notchSpacerWidth = 0
            return
        }

        // Check if this is the built-in display
        let screenName = screen.localizedName
        let newIsBuiltin = screenName.localizedCaseInsensitiveContains("Built-in") ||
                           screenName.localizedCaseInsensitiveContains("Built in")

        // Check for notch via safe area insets (macOS 12.0+)
        var newHasNotch = false
        var newNotchSpacerWidth: CGFloat = 0

        if #available(macOS 12.0, *) {
            let safeArea = screen.safeAreaInsets
            // safeAreaInsets.top > 0 indicates a notch
            newHasNotch = safeArea.top > 0

            if newHasNotch {
                // The MacBook Pro notch is ~200pt wide, centered at the top
                // The spacer needs to be wide enough to keep left/right content
                // from going under the notch. We use ~220pt to provide some margin.
                newNotchSpacerWidth = 220
            }
        }

        // Update published properties
        isBuiltinDisplay = newIsBuiltin
        hasNotch = newHasNotch
        notchSpacerWidth = newNotchSpacerWidth
    }
}
