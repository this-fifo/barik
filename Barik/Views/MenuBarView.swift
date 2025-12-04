import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared
    @ObservedObject var displayManager = DisplayManager.shared

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let allItems = configManager.config.rootToml.widgets.displayed
        let hiddenWidgets = displayManager.isBuiltinDisplay
            ? configManager.config.builtinDisplay.hiddenWidgets
            : []
        let items = allItems.filter { !hiddenWidgets.contains($0.id) }

        HStack(spacing: 0) {
            HStack(spacing: configManager.config.experimental.foreground.spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    let item = items[index]
                    buildView(for: item)
                }
            }

            if !items.contains(where: { $0.id == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, configManager.config.experimental.foreground.horizontalPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
    }

    @ViewBuilder
    private func buildView(for item: TomlWidgetItem) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.system":
            SystemWidget().environmentObject(config)

        case "default.spaces":
            SpacesWidget().environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager(configProvider: config))
                .environmentObject(config)

        case "default.nextmeeting":
            NextMeetingWidget(calendarManager: CalendarManager(configProvider: config))
                .environmentObject(config)

        case "default.nowplaying":
            NowPlayingWidget()
                .environmentObject(config)

        case "default.audiooutput":
            AudioOutputWidget()
                .environmentObject(config)

        case "default.caffeinate":
            CaffeinateWidget()
                .environmentObject(config)

        case "default.iterm":
            ITermWidget()
                .environmentObject(config)

        case "spacer":
            // On notched displays, ensure spacer is wide enough to keep content out of notch
            let minWidth = max(50, displayManager.notchSpacerWidth)
            Spacer().frame(minWidth: minWidth, maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color.foregroundOutside.opacity(0.5))
                .frame(width: 2, height: 15)
                .clipShape(Capsule())

        case "system-banner":
            SystemBannerWidget()

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }
}
