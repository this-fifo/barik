// ABOUTME: Manages system sleep prevention using IOKit power assertions
// ABOUTME: Inspired by KeepingYouAwake (https://github.com/newmarcel/KeepingYouAwake) by Marcel Dierkes

import Foundation
import IOKit.pwr_mgt

/// Manages caffeinate state using IOKit power assertions.
/// When active, prevents system idle sleep while allowing display sleep.
class CaffeinateManager: ObservableObject {
    static let shared = CaffeinateManager()

    @Published private(set) var isActive: Bool = false

    private var assertionID: IOPMAssertionID = 0
    private let assertionName = "Barik Caffeinate Widget" as CFString

    private init() {}

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    func activate() {
        guard !isActive else { return }

        // kIOPMAssertionTypePreventUserIdleSystemSleep prevents system sleep
        // but allows the display to sleep - exactly what we want
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionName,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
        } else {
            print("CaffeinateManager: Failed to create assertion, error: \(result)")
        }
    }

    func deactivate() {
        guard isActive else { return }

        let result = IOPMAssertionRelease(assertionID)

        if result == kIOReturnSuccess {
            isActive = false
            assertionID = 0
        } else {
            print("CaffeinateManager: Failed to release assertion, error: \(result)")
        }
    }

    deinit {
        if isActive {
            deactivate()
        }
    }
}
