import Foundation

@objc public protocol FanHelperProtocol {
    func setManual(
        fanIndex: Int,
        targetRPM: Double,
        leaseID: NSUUID,
        expiresAt: NSDate,
        withReply reply: @escaping (NSError?) -> Void
    )

    func renew(leaseID: NSUUID, expiresAt: NSDate, withReply reply: @escaping (NSError?) -> Void)
    func restoreAutomatic(fanIndices: [NSNumber], withReply reply: @escaping (NSError?) -> Void)
    func status(withReply reply: @escaping ([String: Any]) -> Void)
}
