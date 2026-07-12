import Darwin
import Foundation
import MacPilotFan

Task { @MainActor in
    do {
        try await FanHelperClient().restoreAutomatic(fanIndices: [0, 1])
        print("MacPilot: both fans restored to Apple automatic control")
        exit(0)
    } catch {
        fputs("MacPilot fan recovery failed: \(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()
