// ABOUTME: Watches iTerm2 session JSON files and maintains session state
// ABOUTME: Uses FSEvents to monitor ~/.config/barik/iterm-sessions/ directory

import Foundation
import Combine

struct ITermSession: Identifiable, Codable {
    var id: String { sessionId }
    let sessionId: String
    var command: String?
    var state: SessionState
    var startedAt: Date?
    var completedAt: Date?
    var cwd: String?
    var exitCode: Int?
    var detail: String?

    enum SessionState: String, Codable {
        case idle
        case running
        case toolUse = "tool_use"
        case thinking
        case waiting
        case completed
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case command
        case state
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case cwd
        case exitCode = "exit_code"
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        state = try container.decodeIfPresent(SessionState.self, forKey: .state) ?? .idle
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)

        if let timestamp = try container.decodeIfPresent(Int.self, forKey: .startedAt) {
            startedAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        if let timestamp = try container.decodeIfPresent(Int.self, forKey: .completedAt) {
            completedAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
    }
}

class ITermSessionManager: ObservableObject {
    static let shared = ITermSessionManager()

    @Published private(set) var sessions: [ITermSession] = []

    private let sessionsDirectory: URL
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private var refreshTimer: Timer?

    var sessionCount: Int { sessions.count }
    var hasActivity: Bool { sessions.contains { $0.state == .running || $0.state == .toolUse || $0.state == .thinking } }
    var hasWaiting: Bool { sessions.contains { $0.state == .waiting } }
    var hasFailure: Bool { sessions.contains { $0.exitCode != nil && $0.exitCode != 0 } }

    private init() {
        sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/barik/iterm-sessions")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        startMonitoring()
        startPeriodicRefresh()
        loadSessions()
    }

    private func startPeriodicRefresh() {
        // FSEvents on directories doesn't reliably detect file content changes
        // Poll every second to catch state transitions (running → idle)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.loadSessions()
        }
    }

    private func startMonitoring() {
        directoryDescriptor = open(sessionsDirectory.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            print("ITermSessionManager: Failed to open directory for monitoring")
            return
        }

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        fileMonitor?.setEventHandler { [weak self] in
            self?.loadSessions()
        }

        fileMonitor?.setCancelHandler { [weak self] in
            if let fd = self?.directoryDescriptor, fd >= 0 {
                close(fd)
            }
        }

        fileMonitor?.resume()
    }

    private func loadSessions() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            sessions = []
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()

        var loadedSessions: [ITermSession] = []
        let now = Date()
        let idleStaleThreshold = now.addingTimeInterval(-300) // 5 minutes for completed
        let runningStaleThreshold = now.addingTimeInterval(-86400) // 24 hours for orphaned "running"

        for file in jsonFiles {
            guard let data = try? Data(contentsOf: file),
                  let session = try? decoder.decode(ITermSession.self, from: data) else {
                continue
            }

            // Get file modification time to detect orphaned sessions
            let fileModTime = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast

            // Skip stale idle/completed sessions (5 min after completion)
            if session.state == .idle || session.state == .completed {
                if let completed = session.completedAt, completed < idleStaleThreshold {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
            }

            // Only cleanup "running" sessions after 24h - these are definitely orphaned from Cmd+W
            // (Long-running commands like `claude`, `npm run dev` are legitimate)
            if session.state == .running && fileModTime < runningStaleThreshold {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            loadedSessions.append(session)
        }

        sessions = loadedSessions.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    deinit {
        refreshTimer?.invalidate()
        fileMonitor?.cancel()
    }
}
