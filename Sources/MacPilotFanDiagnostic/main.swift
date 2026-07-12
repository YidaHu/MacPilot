import Foundation
import MacPilotFan

do {
    let connection = try AppleSMCConnection()
    let snapshot = try IntelFanReader(reader: connection).readSnapshot()
    for fan in snapshot.fans {
        let minimum = fan.minimumRPM.map { String(format: "%.0f", $0) } ?? "unknown"
        let maximum = fan.maximumRPM.map { String(format: "%.0f", $0) } ?? "unknown"
        let target = fan.targetRPM.map { String(format: "%.0f", $0) } ?? "unknown"
        print("fan=\(fan.index) actual=\(Int(fan.actualRPM)) min=\(minimum) max=\(maximum) target=\(target) control=\(fan.controlAvailability)")
    }
} catch {
    fputs("MacPilotFanDiagnostic: \(error)\n", stderr)
    exit(1)
}
