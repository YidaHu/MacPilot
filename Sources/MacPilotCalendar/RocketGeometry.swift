import CoreGraphics

public struct RocketGeometry: Equatable {
    public let size: CGSize
    public init(size: CGSize) { self.size = size }

    public var bodyRect: CGRect {
        CGRect(x: 42, y: 38, width: 90, height: 54).scaled(to: size)
    }

    public var noseTip: CGPoint {
        CGPoint(x: 170 * size.width / 180, y: 65 * size.height / 130)
    }

    public var flightAngleRadians: CGFloat { 0 }
}

private extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: origin.x * size.width / 180,
            y: origin.y * size.height / 130,
            width: width * size.width / 180,
            height: height * size.height / 130
        )
    }
}
