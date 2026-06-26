import XCTest
@testable import WindowManagerCore

/// 座標系変換（`GeometryMath`）の純ロジックテスト。
/// bottom-left（AppKit）⇄ top-left（CoreGraphics/AX）の反転を検証する。
final class GeometryMathTests: XCTestCase {

    /// 画面最下部（bottom-left の原点 0）にあるウィンドウは top-left では
    /// `primaryHeight - height` に来る。
    func testFlipYAtBottom() {
        XCTAssertEqual(GeometryMath.flipY(originY: 0, height: 100, primaryHeight: 1080), 980)
    }

    /// 画面最上部に接するウィンドウは top-left で y=0 になる。
    func testFlipYAtTop() {
        // bottom-left の y = primaryHeight - height のとき top-left の y は 0。
        XCTAssertEqual(GeometryMath.flipY(originY: 980, height: 100, primaryHeight: 1080), 0)
    }

    /// 反転は対合（2 回適用すると元に戻る）であること。
    func testFlipYIsInvolution() {
        let h = 200.0, ph = 1440.0
        let once = GeometryMath.flipY(originY: 300, height: h, primaryHeight: ph)
        let twice = GeometryMath.flipY(originY: once, height: h, primaryHeight: ph)
        XCTAssertEqual(twice, 300, accuracy: 1e-9)
    }

    /// 矩形変換では X・幅・高さは不変で、Y のみ反転されること。
    func testFlipRectKeepsXWidthHeight() {
        let r = Rect(x: 50, y: 0, width: 800, height: 600)
        let flipped = GeometryMath.flip(r, primaryHeight: 900)
        XCTAssertEqual(flipped.x, 50)
        XCTAssertEqual(flipped.width, 800)
        XCTAssertEqual(flipped.height, 600)
        XCTAssertEqual(flipped.y, 300) // 900 - (0 + 600)
    }

    /// `flip` を 2 回適用すると元の矩形に戻ること。
    func testFlipRectRoundTrip() {
        let r = Rect(x: 10, y: 120, width: 640, height: 480)
        let back = GeometryMath.flip(GeometryMath.flip(r, primaryHeight: 1080), primaryHeight: 1080)
        XCTAssertEqual(back, r)
    }
}
