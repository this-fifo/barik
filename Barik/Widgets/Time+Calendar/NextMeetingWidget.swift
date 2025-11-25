import EventKit
import SwiftUI

struct NextMeetingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var calendarConfig: ConfigData? { config["calendar"]?.dictionaryValue }

    var maxTitleLength: Int {
        config["max-title-length"]?.intValue ?? 50
    }

    var onlyMeetings: Bool {
        config["only-meetings"]?.boolValue ?? true
    }

    var timeFormat: String {
        calendarConfig?["format"]?.stringValue ?? "J:mm"
    }

    @ObservedObject var calendarManager: CalendarManager

    private var filteredMeeting: EKEvent? {
        if onlyMeetings {
            // Only show events with attendees or meeting links
            return calendarManager.nextMeeting
        } else {
            // Show any upcoming event
            return calendarManager.nextEvent
        }
    }

    var body: some View {
        if let meeting = filteredMeeting {
            HStack(spacing: 4) {
                Text(truncatedTitle(meeting.title ?? "Meeting"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("·")
                    .opacity(0.6)
                Text(timeUntil(meeting.startDate))
            }
            .opacity(0.8)
            .font(.subheadline)
            .foregroundStyle(.foregroundOutside)
            .shadow(color: .foregroundShadowOutside, radius: 3)
            .experimentalConfiguration(cornerRadius: 15)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
        }
    }

    private func truncatedTitle(_ title: String) -> String {
        if title.count <= maxTitleLength {
            return title
        }
        let endIndex = title.index(title.startIndex, offsetBy: maxTitleLength)
        return String(title[..<endIndex]) + "..."
    }

    private func timeUntil(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "now"
        }

        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            if remainingMinutes > 0 {
                return "in \(hours)h \(remainingMinutes)m"
            }
            return "in \(hours)h"
        }

        return "in \(minutes) min"
    }
}

struct NextMeetingWidget_Previews: PreviewProvider {
    static var previews: some View {
        let provider = ConfigProvider(config: ConfigData())
        let manager = CalendarManager(configProvider: provider)

        ZStack {
            NextMeetingWidget(calendarManager: manager)
                .environmentObject(provider)
        }.frame(width: 500, height: 100)
    }
}
