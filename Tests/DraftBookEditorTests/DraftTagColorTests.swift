import AppKit
import DraftBookCore
import XCTest
@testable import DraftBook

final class DraftTagColorTests: XCTestCase {
    func testAgedRedKeepsHueAndBrightnessWhileSaturationDecreases() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let ages = [0, 5, 7, 30].map { days in
            DraftColor.red.agedNSColor(
                createdAt: createdAt,
                referenceDate: createdAt.addingTimeInterval(Double(days) * 86_400)
            )
        }
        let components = ages.map(hsb)
        for color in components.dropFirst() {
            XCTAssertEqual(color.hue, components[0].hue, accuracy: 0.0001)
            XCTAssertEqual(color.brightness, components[0].brightness, accuracy: 0.0001)
        }
        XCTAssertGreaterThan(components[0].saturation, components[1].saturation)
        XCTAssertGreaterThan(components[1].saturation, components[2].saturation)
        XCTAssertGreaterThan(components[2].saturation, components[3].saturation)
    }

    func testUnclassifiedTagLightensThroughGrayWithoutTransparency() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let fresh = DraftColor.gray.agedNSColor(createdAt: createdAt, referenceDate: createdAt)
        let old = DraftColor.gray.agedNSColor(
            createdAt: createdAt,
            referenceDate: createdAt.addingTimeInterval(30 * 86_400)
        )
        XCTAssertEqual(fresh.alphaComponent, 1)
        XCTAssertEqual(old.alphaComponent, 1)
        XCTAssertGreaterThan(hsb(old).brightness, hsb(fresh).brightness)
    }

    private func hsb(_ color: NSColor) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let resolved = color.usingColorSpace(.deviceRGB)!
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (hue, saturation, brightness)
    }
}
