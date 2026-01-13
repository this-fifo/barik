import SwiftUI

struct SpacesWidget: View {
    @StateObject var viewModel = SpacesViewModel()

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {
        HStack(spacing: foregroundHeight < 30 ? 0 : 4) {
            ForEach(viewModel.spaces) { space in
                SpaceView(space: space)
            }
        }
        .experimentalConfiguration(horizontalPadding: 5, cornerRadius: 10)
        .animation(.smooth(duration: 0.15), value: viewModel.spaces)
        .foregroundStyle(Color.foreground)
        .environmentObject(viewModel)
    }
}

// MARK: - Window Group (for compact mode)

/// Groups windows by app name for compact display
struct WindowGroup: Identifiable {
    let id: String  // appName
    let appName: String
    let appIcon: NSImage?
    let windows: [AnyWindow]

    var hasFocusedWindow: Bool {
        windows.contains { $0.isFocused }
    }
}

/// This view shows a space with its windows.
private struct SpaceView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var spaceConfig: ConfigData { config["space"]?.dictionaryValue ?? [:] }

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var showKey: Bool { spaceConfig["show-key"]?.boolValue ?? true }
    var compactMode: Bool { config["compact-mode"]?.boolValue ?? false }

    let space: AnySpace

    @State var isHovered = false

    /// Group windows by app name for compact mode
    var windowGroups: [WindowGroup] {
        var groups: [String: [AnyWindow]] = [:]
        var order: [String] = []

        for window in space.windows {
            let key = window.appName ?? "Unknown"
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(window)
        }

        return order.compactMap { appName in
            guard let windows = groups[appName], let first = windows.first else { return nil }
            return WindowGroup(
                id: "\(space.id)-\(appName)",
                appName: appName,
                appIcon: first.appIcon,
                windows: windows
            )
        }
    }

    var body: some View {
        let isFocused = space.windows.contains { $0.isFocused } || space.isFocused
        HStack(spacing: 0) {
            Spacer().frame(width: 6)
            if showKey {
                Text(space.id)
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 15)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer().frame(width: 4)
            }
            HStack(spacing: 2) {
                if compactMode {
                    ForEach(windowGroups) { group in
                        WindowGroupView(group: group, space: space)
                    }
                } else {
                    ForEach(space.windows) { window in
                        WindowView(window: window, space: space)
                    }
                }
            }
            Spacer().frame(width: 6)
        }
        .frame(height: 30)
        .background(
            foregroundHeight < 30 ?
            (isFocused
             ? Color.noActive
             : Color.clear) :
                (isFocused
                 ? Color.active
                 : isHovered ? Color.noActive : Color.noActive)
        )
        .clipShape(RoundedRectangle(cornerRadius: foregroundHeight < 30 ? 0 : 8, style: .continuous))
        .shadow(color: .shadow, radius: foregroundHeight < 30 ? 0 : 2)
        .transition(.blurReplace)
        .onTapGesture {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        .animation(.smooth, value: isHovered)
        .onHover { value in
            isHovered = value
        }
    }
}

/// This view shows a window and its icon.
private struct WindowView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel
    @ObservedObject var displayManager = DisplayManager.shared

    var config: ConfigData { configProvider.config }
    var windowConfig: ConfigData { config["window"]?.dictionaryValue ?? [:] }
    var titleConfig: ConfigData {
        windowConfig["title"]?.dictionaryValue ?? [:]
    }

    var showTitle: Bool { windowConfig["show-title"]?.boolValue ?? true }
    var maxLength: Int { titleConfig["max-length"]?.intValue ?? 50 }
    var alwaysDisplayAppTitleFor: [String] { titleConfig["always-display-app-name-for"]?.arrayValue?.filter({ $0.stringValue != nil }).map { $0.stringValue! } ?? [] }

    let window: AnyWindow
    let space: AnySpace

    @State var isHovered = false

    // Hide titles on notched displays to prevent overflow
    var effectiveShowTitle: Bool {
        showTitle && !displayManager.hasNotch
    }

    var body: some View {
        let titleMaxLength = maxLength
        let size: CGFloat = 21
        let sameAppCount = space.windows.filter { $0.appName == window.appName }
            .count
        let title = sameAppCount > 1 && !alwaysDisplayAppTitleFor.contains { $0 == window.appName } ? window.title : (window.appName ?? "")
        let spaceIsFocused = space.windows.contains { $0.isFocused }
        HStack {
            ZStack {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(
                            color: .iconShadow,
                            radius: 2
                        )
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            .opacity(spaceIsFocused && !window.isFocused ? 0.5 : 1)
            .transition(.blurReplace)

            if window.isFocused, !title.isEmpty, effectiveShowTitle {
                HStack {
                    Text(
                        title.count > titleMaxLength
                            ? String(title.prefix(titleMaxLength)) + "..."
                            : title
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .shadow(color: .foregroundShadow, radius: 3)
                    .fontWeight(.medium)
                    Spacer().frame(width: 5)
                }
                .transition(.blurReplace)
            }
        }
        .padding(.all, 2)
        .background(isHovered || (!effectiveShowTitle && window.isFocused) ? .selected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.smooth, value: isHovered)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.switchToSpace(space)
            usleep(100_000)
            viewModel.switchToWindow(window)
        }
        .onHover { value in
            isHovered = value
        }
    }
}

// MARK: - Window Group View (Compact Mode)

/// A collapsed view showing a single icon for grouped windows, with popover on hover
private struct WindowGroupView: View {
    @EnvironmentObject var viewModel: SpacesViewModel
    @ObservedObject var displayManager = DisplayManager.shared

    let group: WindowGroup
    let space: AnySpace

    @State private var isHovered = false
    @State private var popoverFrame: CGRect = .zero

    private let iconSize: CGFloat = 21

    var body: some View {
        ZStack {
            if let icon = group.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .iconShadow, radius: 2)
            } else {
                Image(systemName: "questionmark.circle")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
        }
        .opacity(space.isFocused && !group.hasFocusedWindow ? 0.5 : 1)
        .padding(.all, 2)
        .background(isHovered || group.hasFocusedWindow ? Color.selected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.smooth(duration: 0.1), value: isHovered)
        .frame(height: 30)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { popoverFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        popoverFrame = newFrame
                    }
            }
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering && group.windows.count > 1 {
                showPopover()
            } else if !hovering {
                hidePopover()
            }
        }
        .onTapGesture {
            // Click focuses first window in group
            if let firstWindow = group.windows.first {
                viewModel.switchToSpace(space)
                usleep(100_000)
                viewModel.switchToWindow(firstWindow)
            }
        }
    }

    private func showPopover() {
        WindowGroupPopover.show(
            group: group,
            space: space,
            anchorFrame: popoverFrame,
            viewModel: viewModel,
            hasNotch: displayManager.hasNotch
        )
    }

    private func hidePopover() {
        WindowGroupPopover.scheduleHide()
    }
}

// MARK: - Window Group Popover

/// Glassmorphism popover showing all windows in a group
class WindowGroupPopover {
    private static var panel: NSPanel?
    private static var hideTimer: Timer?
    private static var isMouseInside = false

    static func show(
        group: WindowGroup,
        space: AnySpace,
        anchorFrame: CGRect,
        viewModel: SpacesViewModel,
        hasNotch: Bool
    ) {
        hideTimer?.invalidate()
        hideTimer = nil

        // Dismiss existing panel
        panel?.close()

        // Create content view
        let contentView = WindowGroupPopoverContent(
            group: group,
            space: space,
            viewModel: viewModel,
            hasNotch: hasNotch,
            onHoverChange: { inside in
                isMouseInside = inside
                if !inside {
                    scheduleHide()
                } else {
                    hideTimer?.invalidate()
                    hideTimer = nil
                }
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.setFrameSize(hostingView.fittingSize)

        // Convert SwiftUI coordinates (origin top-left) to AppKit (origin bottom-left)
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let screenFrame = screen.visibleFrame

        let popoverWidth = hostingView.fittingSize.width
        let popoverHeight = hostingView.fittingSize.height

        // anchorFrame.maxY in SwiftUI = distance from top of screen
        // In AppKit, we need: screenHeight - swiftUI_Y
        let appKitAnchorBottom = screenHeight - anchorFrame.maxY

        // Position popover below the anchor, clamped to screen bounds
        var x = anchorFrame.midX - popoverWidth / 2
        let y = appKitAnchorBottom - popoverHeight - 4

        // Clamp X to stay within screen margins (8px padding)
        let minX = screenFrame.minX + 8
        let maxX = screenFrame.maxX - popoverWidth - 8
        x = max(minX, min(x, maxX))

        let newPanel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: popoverWidth, height: popoverHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.level = .popUpMenu
        newPanel.hasShadow = false
        newPanel.contentView = hostingView
        newPanel.isMovable = false

        // Animate in
        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1
        }

        panel = newPanel
        isMouseInside = false
    }

    static func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            if !isMouseInside {
                hide()
            }
        }
    }

    static func hide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard let currentPanel = panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            currentPanel.animator().alphaValue = 0
        }, completionHandler: {
            currentPanel.close()
            if panel === currentPanel {
                panel = nil
            }
        })
    }
}

// MARK: - Popover Content View

private struct WindowGroupPopoverContent: View {
    let group: WindowGroup
    let space: AnySpace
    let viewModel: SpacesViewModel
    let hasNotch: Bool
    let onHoverChange: (Bool) -> Void

    // Adaptive max title length based on display
    private var maxTitleLength: Int {
        hasNotch ? 25 : 50
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(group.windows) { window in
                WindowRowView(
                    window: window,
                    space: space,
                    viewModel: viewModel,
                    maxTitleLength: maxTitleLength
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }
}

// MARK: - Window Row View

private struct WindowRowView: View {
    let window: AnyWindow
    let space: AnySpace
    let viewModel: SpacesViewModel
    let maxTitleLength: Int

    @State private var isHovered = false

    private let iconSize: CGFloat = 18
    private let rowHeight: CGFloat = 28

    private var displayTitle: String {
        let title = window.title.isEmpty ? (window.appName ?? "Unknown") : window.title
        if title.count > maxTitleLength {
            return String(title.prefix(maxTitleLength)) + "..."
        }
        return title
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: "questionmark.circle")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }

            Text(displayTitle)
                .font(.system(size: 12))
                .fontWeight(window.isFocused ? .medium : .regular)
                .foregroundColor(window.isFocused ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            WindowGroupPopover.hide()
            viewModel.switchToSpace(space)
            usleep(100_000)
            viewModel.switchToWindow(window)
        }
    }
}
