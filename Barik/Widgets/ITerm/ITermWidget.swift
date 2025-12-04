// ABOUTME: Widget showing iTerm2 session count with activity indicator
// ABOUTME: Click to show session details popup

import SwiftUI

struct ITermWidget: View {
    @ObservedObject private var manager = ITermSessionManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 12))
                .foregroundStyle(iconColor)

            if manager.sessionCount > 0 {
                Text("\(manager.sessionCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.foregroundOutside)
            }

            // Show orange dot if ANY session is waiting (needs attention)
            if manager.hasWaiting {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .shadow(color: .orange.opacity(0.5), radius: 2)
            }
            // Show blue dot if ANY session has activity
            if manager.hasActivity {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
                    .shadow(color: .blue.opacity(0.5), radius: 2)
            }
        }
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newValue in
                        rect = newValue
                    }
            }
        )
        .background(.black.opacity(0.001))
        .onTapGesture {
            ITermPopoverManager.shared.toggle(relativeTo: rect) {
                ITermPopoverView(sessions: manager.sessions)
            }
        }
    }

    private var iconColor: Color {
        if manager.hasFailure {
            return .red
        } else if manager.hasActivity {
            return .blue
        } else if manager.hasWaiting {
            return .orange
        } else if manager.sessionCount > 0 {
            return .foregroundOutside
        } else {
            return .foregroundOutside.opacity(0.5)
        }
    }
}

struct ITermPopoverView: View {
    let sessions: [ITermSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(sessions) { session in
                    ITermSessionRow(session: session)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }
}

struct ITermSessionRow: View {
    let session: ITermSession

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(commandDisplay)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)

                    Spacer()

                    if let duration = durationText {
                        Text(duration)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(directoryDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if session.state == .idle || session.state == .completed {
                        if let exit = session.exitCode {
                            Text(exit == 0 ? "✓" : "✗ \(exit)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(exit == 0 ? .green : .red)
                        }
                    } else {
                        Text(stateLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(stateColor)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var commandDisplay: String {
        if let command = session.command, !command.isEmpty {
            // Show full command, truncation handled by lineLimit
            return "$ \(command)"
        }
        return "$ fish"
    }

    private var directoryDisplay: String {
        guard let cwd = session.cwd else { return "~" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    private var stateLabel: String {
        switch session.state {
        case .running:
            return "running"
        case .toolUse:
            return "tool"
        case .thinking:
            return "thinking"
        case .waiting:
            return "waiting"
        case .idle, .completed:
            return ""
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .idle:
            if let exit = session.exitCode, exit != 0 {
                return .red
            }
            return .green
        case .running:
            return .yellow
        case .toolUse, .thinking:
            return .blue
        case .waiting:
            return .orange
        case .completed:
            if let exit = session.exitCode, exit != 0 {
                return .red
            }
            return .green
        }
    }

    private var durationText: String? {
        guard let started = session.startedAt else { return nil }

        let elapsed: TimeInterval
        if let completed = session.completedAt {
            elapsed = completed.timeIntervalSince(started)
        } else if session.state == .running || session.state == .toolUse || session.state == .thinking {
            elapsed = Date().timeIntervalSince(started)
        } else {
            return nil
        }

        if elapsed < 60 {
            return "\(Int(elapsed))s"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        } else {
            return "\(Int(elapsed / 3600))h \(Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }
}

struct ITermWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            ITermWidget()
        }
        .frame(width: 100, height: 50)
        .background(.gray)
    }
}
