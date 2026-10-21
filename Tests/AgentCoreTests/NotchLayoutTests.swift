import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import AgentCore

@Test func notchContentLeavesCameraGap() {
    let geometry = NotchLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32,
                               leftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
                               rightArea: CGRect(x: 856, y: 950, width: 656, height: 32), expanded: false)
    #expect(geometry.cameraWidth == 200)
    #expect(geometry.frame.midX == 756)
    #expect(geometry.frame.maxY == 982)
    #expect(geometry.frame.width >= geometry.cameraWidth + 160)
}

@Test func virtualNotchWorksOnOffsetExternalDisplay() {
    let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
    let geometry = NotchLayout(screen: screen, topInset: 0, leftArea: nil, rightArea: nil, expanded: true)
    #expect(geometry.cameraWidth == 0)
    #expect(geometry.frame.midX == screen.midX)
    #expect(geometry.frame.maxY == screen.maxY)
    #expect(geometry.frame.height == 292)
}

@Test func notchFrameFitsSmallDisplays() {
    let screen = CGRect(x: 100, y: -400, width: 320, height: 240)
    let geometry = NotchLayout(screen: screen, topInset: 0, leftArea: nil, rightArea: nil, expanded: true)
    #expect(screen.contains(geometry.frame))
}
