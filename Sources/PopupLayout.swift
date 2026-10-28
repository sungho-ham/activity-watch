import Foundation
import CoreGraphics

enum PopupLayout {
    static let width: CGFloat = 560
    static let baseHeight: CGFloat = 400
    static let detailHeight: CGFloat = 238
    static let dividerHeight: CGFloat = 1

    /// Keep the title bar and summary stationary; use the available space below them.
    static func frame(from current: CGRect, chromeHeight: CGFloat, screen: CGRect?, expanded: Bool) -> CGRect {
        let collapsedHeight = baseHeight + chromeHeight
        let desired = collapsedHeight + (expanded ? detailHeight + dividerHeight : 0)
        let available = screen.map { max(collapsedHeight, current.maxY - $0.minY) } ?? desired
        let height = min(desired, available)
        return CGRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
    }
}
