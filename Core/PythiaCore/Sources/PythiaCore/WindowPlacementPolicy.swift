import Foundation

public enum PythiaWindowPlacementPolicy {
    public static func fittedSize(preferred: CGSize, minimum: CGSize, visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(max(minimum.width, preferred.width), max(1, visibleFrame.size.width)),
            height: min(max(minimum.height, preferred.height), max(1, visibleFrame.size.height))
        )
    }

    public static func clampedFrame(_ frame: CGRect, minimum: CGSize, visibleFrame: CGRect) -> CGRect {
        var result = frame
        result.size = fittedSize(preferred: frame.size, minimum: minimum, visibleFrame: visibleFrame)
        let visibleMaxX = visibleFrame.origin.x + visibleFrame.size.width
        let visibleMaxY = visibleFrame.origin.y + visibleFrame.size.height
        if result.origin.x + result.size.width > visibleMaxX { result.origin.x = visibleMaxX - result.size.width }
        if result.origin.x < visibleFrame.origin.x { result.origin.x = visibleFrame.origin.x }
        if result.origin.y + result.size.height > visibleMaxY { result.origin.y = visibleMaxY - result.size.height }
        if result.origin.y < visibleFrame.origin.y { result.origin.y = visibleFrame.origin.y }
        return result
    }

    public static func bestScreenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        screens.indices.max { lhs, rhs in
            intersectionArea(screens[lhs], frame) < intersectionArea(screens[rhs], frame)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let left = max(lhs.origin.x, rhs.origin.x)
        let right = min(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
        let bottom = max(lhs.origin.y, rhs.origin.y)
        let top = min(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)
        guard right > left, top > bottom else { return 0 }
        return (right - left) * (top - bottom)
    }
}
