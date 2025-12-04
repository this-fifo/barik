// ABOUTME: Custom NSPopover wrapper with proper window level for menu bar apps
// ABOUTME: Provides native popover appearance while appearing above all windows

import SwiftUI
import AppKit

class ITermPopoverManager: NSObject, NSPopoverDelegate {
    static let shared = ITermPopoverManager()

    private var popover: NSPopover?
    private var positioningView: NSView?

    private override init() {
        super.init()
    }

    func toggle<Content: View>(relativeTo rect: CGRect, content: @escaping () -> Content) {
        if let popover = popover, popover.isShown {
            popover.close()
            return
        }

        show(relativeTo: rect, content: content)
    }

    func show<Content: View>(relativeTo rect: CGRect, content: @escaping () -> Content) {
        // Close existing popover if any
        popover?.close()
        cleanup()

        let newPopover = NSPopover()
        newPopover.contentViewController = NSHostingController(rootView: content())
        newPopover.behavior = .transient
        newPopover.animates = true
        newPopover.delegate = self

        self.popover = newPopover

        // Find the Barik window
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.frame.intersects(rect)
        }) else { return }

        // Convert rect to window coordinates
        let windowRect = window.convertFromScreen(rect)

        // Create a positioning view and keep it around
        let view = NSView(frame: windowRect)
        window.contentView?.addSubview(view)
        self.positioningView = view

        newPopover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)

        // Raise the popover window above other windows
        DispatchQueue.main.async {
            if let popoverWindow = newPopover.contentViewController?.view.window {
                popoverWindow.level = .floating
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
        positioningView?.removeFromSuperview()
        positioningView = nil
        popover = nil
    }
}
