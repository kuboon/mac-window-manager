import AppKit
import CoreGraphics

/// 座標系変換を 1 箇所に集約する。
///
/// - AppKit (`NSScreen`/`NSWindow`) は **bottom-left 原点**
/// - CoreGraphics / Accessibility (`kAXPosition` / `CGWindowBounds` / `CGDisplayBounds`) は **top-left 原点**
///
/// Ruby 側へ渡す座標はすべて **top-left に統一**する。本ファイルがその唯一の変換境界。
enum Geometry {
    /// グローバルな「デスクトップ全体の高さ」。複数ディスプレイをまたぐ Y 反転に使う。
    /// 全 display を含む union 矩形の最大 Y（top-left 基準）を返す。
    static var globalMaxY: CGFloat {
        // CGDisplayBounds は top-left 基準なので、全 display の maxY の最大値。
        var union = CGRect.zero
        for screen in NSScreen.screens {
            union = union.union(cgFrame(of: screen))
        }
        return union.maxY
    }

    /// NSScreen.frame (bottom-left) を top-left 原点の CGRect に変換する。
    static func cgFrame(of screen: NSScreen) -> CGRect {
        // メインスクリーン（screens.first ではなく、原点を持つ画面）の高さを基準に反転。
        guard let primary = NSScreen.screens.first else { return screen.frame }
        let primaryHeight = primary.frame.height
        let f = screen.frame
        // bottom-left → top-left: newY = primaryHeight - (y + height)
        return CGRect(x: f.origin.x,
                      y: primaryHeight - (f.origin.y + f.height),
                      width: f.width,
                      height: f.height)
    }

    /// NSScreen.visibleFrame (bottom-left) を top-left 原点に変換する。
    static func cgVisibleFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.visibleFrame }
        let primaryHeight = primary.frame.height
        let f = screen.visibleFrame
        return CGRect(x: f.origin.x,
                      y: primaryHeight - (f.origin.y + f.height),
                      width: f.width,
                      height: f.height)
    }
}
