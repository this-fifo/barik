import Foundation
import AppKit

/// Manages system sleep/wake events and notifies observers to pause/resume services.
/// This significantly improves battery life by stopping timers and background tasks during sleep.
class SleepWakeManager {
    static let shared = SleepWakeManager()
    
    /// Notification posted when the system is about to sleep
    static let willSleepNotification = NSNotification.Name("com.barik.willSleep")
    
    /// Notification posted when the system wakes from sleep
    static let didWakeNotification = NSNotification.Name("com.barik.didWake")
    
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        
        // Observe system sleep
        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillSleep()
        }
        
        // Observe system wake
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidWake()
        }
    }
    
    private func stopMonitoring() {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    private func handleWillSleep() {
        // Post notification for widgets to pause their services
        NotificationCenter.default.post(name: SleepWakeManager.willSleepNotification, object: nil)
    }
    
    private func handleDidWake() {
        // Post notification for widgets to resume their services
        NotificationCenter.default.post(name: SleepWakeManager.didWakeNotification, object: nil)
    }
}
