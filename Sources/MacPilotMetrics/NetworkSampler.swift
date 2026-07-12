import CoreWLAN
import Darwin
import Foundation
import MacPilotCore
import SystemConfiguration

public struct NetworkCounters: Equatable {
    public let received: UInt64
    public let sent: UInt64
    public let at: Date

    public init(received: UInt64, sent: UInt64, at: Date) {
        self.received = received
        self.sent = sent
        self.at = at
    }
}

public struct NetworkRate: Equatable {
    public let download: UInt64
    public let upload: UInt64

    public static let zero = NetworkRate(download: 0, upload: 0)

    public init(download: UInt64, upload: UInt64) {
        self.download = download
        self.upload = upload
    }

    public static func between(_ previous: NetworkCounters, _ current: NetworkCounters) -> NetworkRate {
        let elapsed = current.at.timeIntervalSince(previous.at)
        guard elapsed > 0,
              current.received >= previous.received,
              current.sent >= previous.sent else {
            return .zero
        }
        return NetworkRate(
            download: UInt64(Double(current.received - previous.received) / elapsed),
            upload: UInt64(Double(current.sent - previous.sent) / elapsed)
        )
    }
}

public struct NetworkRiskAssessment: Equatable {
    public let risk: NetworkSnapshot.Risk
    public let explanation: String
}

public enum NetworkRiskEvaluator {
    public static func evaluate(
        isWiFi: Bool,
        isEncryptedWiFi: Bool?,
        hasVPN: Bool,
        hasProxy: Bool
    ) -> NetworkRiskAssessment {
        if hasVPN {
            return .init(risk: .normal, explanation: "VPN 已连接")
        }
        if hasProxy {
            return .init(risk: .normal, explanation: "系统代理已启用")
        }
        if isWiFi, isEncryptedWiFi == false {
            return .init(risk: .attention, explanation: "当前 Wi-Fi 未加密")
        }
        if isWiFi, isEncryptedWiFi == nil {
            return .init(risk: .unknown, explanation: "无法确认 Wi-Fi 加密状态")
        }
        return .init(risk: .normal, explanation: isWiFi ? "Wi-Fi 已加密" : "有线网络已连接")
    }
}

public enum NetworkSamplerError: Error {
    case interfaceEnumerationFailed(Int32)
    case noActiveInterface
}

public final class NetworkSampler: @unchecked Sendable {
    private struct InterfaceSample {
        let name: String
        let received: UInt64
        let sent: UInt64
        let ipv4: String?
    }

    private let lock = NSLock()
    private var previous: (name: String, counters: NetworkCounters)?

    public init() {}

    public func sample(at date: Date = Date()) throws -> NetworkSnapshot {
        let interfaces = try activeInterfaces()
        guard let primary = interfaces.first(where: { $0.name == "en0" }) ?? interfaces.first else {
            throw NetworkSamplerError.noActiveInterface
        }
        let counters = NetworkCounters(received: primary.received, sent: primary.sent, at: date)

        lock.lock()
        let rate: NetworkRate
        if let previous, previous.name == primary.name {
            rate = NetworkRate.between(previous.counters, counters)
        } else {
            rate = .zero
        }
        previous = (primary.name, counters)
        lock.unlock()

        let hasVPN = interfaces.contains { nameLooksLikeVPN($0.name) }
        let hasProxy = systemProxyEnabled()
        let isWiFi = primary.name.hasPrefix("en") && CWWiFiClient.shared().interface(withName: primary.name) != nil
        let encrypted = isWiFi ? wifiEncryptionState(interfaceName: primary.name) : nil
        let assessment = NetworkRiskEvaluator.evaluate(
            isWiFi: isWiFi,
            isEncryptedWiFi: encrypted,
            hasVPN: hasVPN,
            hasProxy: hasProxy
        )
        return NetworkSnapshot(
            interfaceName: primary.name,
            ipv4Address: primary.ipv4,
            downloadBytesPerSecond: rate.download,
            uploadBytesPerSecond: rate.upload,
            risk: assessment.risk,
            riskExplanation: assessment.explanation
        )
    }

    private func activeInterfaces() throws -> [InterfaceSample] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        let result = getifaddrs(&firstAddress)
        guard result == 0 else { throw NetworkSamplerError.interfaceEnumerationFailed(errno) }
        defer { freeifaddrs(firstAddress) }

        var samples: [String: InterfaceSample] = [:]
        var cursor = firstAddress
        while let current = cursor {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let required = Int32(IFF_UP | IFF_RUNNING)
            if flags & required == required, flags & Int32(IFF_LOOPBACK) == 0 {
                let name = String(cString: interface.ifa_name)
                let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
                let existing = samples[name]
                let ipv4 = ipv4Address(from: interface.ifa_addr) ?? existing?.ipv4
                samples[name] = InterfaceSample(
                    name: name,
                    received: data.map { UInt64($0.ifi_ibytes) } ?? existing?.received ?? 0,
                    sent: data.map { UInt64($0.ifi_obytes) } ?? existing?.sent ?? 0,
                    ipv4: ipv4
                )
            }
            cursor = interface.ifa_next
        }
        return samples.values.sorted { lhs, rhs in
            if lhs.name == "en0" { return true }
            if rhs.name == "en0" { return false }
            return lhs.name < rhs.name
        }
    }

    private func ipv4Address(from address: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let address, address.pointee.sa_family == UInt8(AF_INET) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        return result == 0 ? String(cString: host) : nil
    }

    private func nameLooksLikeVPN(_ name: String) -> Bool {
        ["utun", "ppp", "ipsec", "tun", "tap"].contains { name.hasPrefix($0) }
    }

    private func systemProxyEnabled() -> Bool {
        guard let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return false }
        let keys = [
            kSCPropNetProxiesHTTPEnable as String,
            kSCPropNetProxiesHTTPSEnable as String,
            kSCPropNetProxiesSOCKSEnable as String
        ]
        return keys.contains { (proxies[$0] as? NSNumber)?.boolValue == true }
    }

    private func wifiEncryptionState(interfaceName: String) -> Bool? {
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName) else { return nil }
        return interface.security() != .none
    }
}
