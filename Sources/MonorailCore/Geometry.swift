import Foundation

/// A rectangle in a top-left-origin coordinate space (the space the
/// Accessibility API uses). Kept independent of CoreGraphics so the layout
/// model builds and tests on any platform.
public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    /// True when the two rects are equal within `tolerance` points on every edge.
    public func isClose(to other: Rect, tolerance: Double = 1) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// Linear interpolation from `self` to `other` at progress `t` (0...1).
    public func interpolated(to other: Rect, t: Double) -> Rect {
        Rect(
            x: x + (other.x - x) * t,
            y: y + (other.y - y) * t,
            width: width + (other.width - width) * t,
            height: height + (other.height - height) * t
        )
    }

    public func rounded() -> Rect {
        Rect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}
