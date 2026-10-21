import AppKit
import SwiftUI
import XCTest
@testable import Classwise

/// The Mac's BYETokens.swift must match the tokens the Windows app vendors from the website
/// (`node scripts/sync-bye-shared.mjs` updates both).
final class TokenDriftTests: XCTestCase {
    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var vendoredTokens: URL { repo.appendingPathComponent("apps/cross-platform/vendor/bye-shared/tokens") }

    func testMacTokenFileMatchesVendoredGeneratedFile() throws {
        let mac = try Data(contentsOf: repo.appendingPathComponent("Sources/Classwise/Views/BYETokens.swift"))
        let vendored = try Data(contentsOf: vendoredTokens.appendingPathComponent("generated/BYETokens.swift"))
        XCTAssertEqual(mac, vendored, "Sources/Classwise/Views/BYETokens.swift drifted; run node scripts/sync-bye-shared.mjs")
    }

    func testColorsMatchTokenJSON() throws {
        let colors: [String: Color] = [
            "paper": BYEColor.paper, "linen": BYEColor.linen, "card": BYEColor.card, "tile": BYEColor.tile,
            "tileLine": BYEColor.tileLine, "ink": BYEColor.ink, "ink2": BYEColor.ink2, "ink3": BYEColor.ink3,
            "line": BYEColor.line, "lineStrong": BYEColor.lineStrong, "accent": BYEColor.accent,
            "brandSoft": BYEColor.brandSoft, "signal": BYEColor.signal,
        ]
        let json = try tokens()["color"] as? [String: [String: Any]] ?? [:]
        XCTAssertEqual(Set(json.keys), Set(colors.keys), "tokens.json colors changed; update this test and the Palette aliases")
        for (name, entry) in json {
            let hex = try XCTUnwrap(entry["value"] as? String)
            XCTAssertEqual(try hexString(XCTUnwrap(colors[name])), hex.lowercased(), name)
        }
    }

    func testSizesAndRadiiMatchTokenJSON() throws {
        let json = try tokens()
        let size = json["size"] as? [String: Double] ?? [:]
        XCTAssertEqual(size["hero"], Double(BYESize.hero))
        XCTAssertEqual(size["body"], Double(BYESize.body))
        XCTAssertEqual(size["caption"], Double(BYESize.caption))
        let radius = json["radius"] as? [String: Double] ?? [:]
        XCTAssertEqual(radius["card"], Double(BYERadius.card))
        XCTAssertEqual(radius["pill"], Double(BYERadius.pill))
    }

    func testPaletteReadsTokens() {
        XCTAssertEqual(Palette.paper, BYEColor.paper)
        XCTAssertEqual(Palette.paper2, BYEColor.linen)
        XCTAssertEqual(Palette.secondary, BYEColor.ink3)
        XCTAssertEqual(Palette.highlight, BYEColor.accent)
    }

    func testReduceMotionTurnsAnimationsOff() {
        XCTAssertNil(BYEMotion.spring(reduce: true))
        XCTAssertNil(BYEMotion.glide(reduce: true))
        XCTAssertNil(BYEMotion.stagger(3, reduce: true))
        XCTAssertNotNil(BYEMotion.glide(reduce: false))
    }

    private func tokens() throws -> [String: Any] {
        let data = try Data(contentsOf: vendoredTokens.appendingPathComponent("tokens.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hexString(_ color: Color) throws -> String {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        let byte = { (value: CGFloat) in Int((value * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
