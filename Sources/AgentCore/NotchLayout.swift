import Foundation

public struct NotchLayout: Sendable, Equatable {
    public let frame: CGRect
    public let cameraWidth: CGFloat
    public let headerHeight: CGFloat

    public init(screen: CGRect, topInset: CGFloat, leftArea: CGRect?, rightArea: CGRect?, expanded: Bool) {
        let gap: CGFloat
        let center: CGFloat
        if topInset > 0, let leftArea, let rightArea, rightArea.minX > leftArea.maxX {
            gap = rightArea.minX - leftArea.maxX
            center = (leftArea.maxX + rightArea.minX) / 2
        } else {
            gap = 0
            center = screen.midX
        }
        cameraWidth = gap
        headerHeight = max(32, topInset)
        let width = min(screen.width, max(expanded ? 440 : 300, gap + 160))
        let height = min(screen.height, headerHeight + (expanded ? 260 : 0))
        let x = min(max(center - width / 2, screen.minX), screen.maxX - width)
        frame = CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
}
