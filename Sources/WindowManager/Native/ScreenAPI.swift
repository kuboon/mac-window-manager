import AppKit
import CoreGraphics

/// Ruby に渡すディスプレイ情報（top-left 原点に変換済み）。
struct ScreenInfo: Codable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let visibleX: Double
    let visibleY: Double
    let visibleW: Double
    let visibleH: Double
    let scale: Double
    let name: String

    enum CodingKeys: String, CodingKey {
        case x, y, w, h, scale, name
        case visibleX = "visible_x"
        case visibleY = "visible_y"
        case visibleW = "visible_w"
        case visibleH = "visible_h"
    }
}

/// NSScreen / Display のラッパ（Part A の §4）。全座標は top-left に統一して返す。
enum ScreenAPI {
    static func listScreens() -> [ScreenInfo] {
        NSScreen.screens.map { screen in
            let frame = Geometry.cgFrame(of: screen)
            let visible = Geometry.cgVisibleFrame(of: screen)
            return ScreenInfo(
                x: frame.origin.x, y: frame.origin.y,
                w: frame.size.width, h: frame.size.height,
                visibleX: visible.origin.x, visibleY: visible.origin.y,
                visibleW: visible.size.width, visibleH: visible.size.height,
                scale: Double(screen.backingScaleFactor),
                name: screen.localizedName
            )
        }
    }
}
