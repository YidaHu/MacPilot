import Foundation
import Security
import ServiceManagement

public enum FanHelperInstallerError: Error {
    case authorization(OSStatus)
    case blessing(CFError?)
}

public struct FanHelperInstaller {
    public static let label = "com.huyida.macpilot.fanhelper"

    public init() {}

    public func install() throws {
        var authorization: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw FanHelperInstallerError.authorization(status)
        }
        defer { AuthorizationFree(authorization, []) }

        status = kSMRightBlessPrivilegedHelper.withCString { rightName in
            var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            throw FanHelperInstallerError.authorization(status)
        }

        var unmanagedError: Unmanaged<CFError>?
        guard SMJobBless(kSMDomainSystemLaunchd, Self.label as CFString, authorization, &unmanagedError) else {
            throw FanHelperInstallerError.blessing(unmanagedError?.takeRetainedValue())
        }
    }
}
