#if canImport(AppKit)
import AppKit
import CoreGraphics
import WindowManagerCore

/// 座標系変換の macOS 側ラッパ。`NSScreen` から寸法を取り出し、純ロジックの
/// `WindowManagerCore.GeometryMath` に反転計算を委譲する。
///
/// - AppKit (`NSScreen`/`NSWindow`) は **bottom-left 原点**
/// - CoreGraphics / Accessibility (`kAXPosition` / `CGWindowBounds` / `CGDisplayBounds`) は **top-left 原点**
///
/// Ruby 側へ渡す座標はすべて **top-left に統一**する。本ファイルがその唯一の変換境界。
enum Geometry {
    /// NSScreen.frame (bottom-left) を top-left 原点の CGRect に変換する。
    static func cgFrame(of screen: NSScreen) -> CGRect {
        convert(screen.frame)
    }

    /// NSScreen.visibleFrame (bottom-left) を top-left 原点に変換する。
    static func cgVisibleFrame(of screen: NSScreen) -> CGRect {
        convert(screen.visibleFrame)
    }

    /// プライマリスクリーン（原点を持つ画面 = screens.first）の高さを基準に Y を反転する。
    private static func convert(_ frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return frame }
        let flipped = GeometryMath.flip(
            Rect(x: frame.origin.x, y: frame.origin.y,
                 width: frame.width, height: frame.height),
            primaryHeight: primary.frame.height
        )
        return CGRect(x: flipped.x, y: flipped.y, width: flipped.width, height: flipped.height)
    }
}
#endif
