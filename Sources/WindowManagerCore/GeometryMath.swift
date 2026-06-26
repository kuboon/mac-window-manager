import Foundation

/// 座標矩形の最小表現（プラットフォーム非依存）。
/// CoreGraphics の `CGRect` に依存せず、Linux でもテストできるよう独自に持つ。
public struct Rect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 座標系変換の **純ロジック**（Apple フレームワーク非依存）。
///
/// - AppKit (`NSScreen`/`NSWindow`) は **bottom-left 原点**
/// - CoreGraphics / Accessibility は **top-left 原点**
///
/// `NSScreen` などに触れる薄いラッパ（`Geometry`）は macOS ターゲット側に置き、
/// 実際の反転計算はここに集約する。こうすることで Linux 上で `swift test` できる。
public enum GeometryMath {

    /// bottom-left 原点の Y を top-left 原点へ反転する。
    ///
    /// - Parameters:
    ///   - originY: bottom-left 基準の矩形原点 Y
    ///   - height: 矩形の高さ
    ///   - primaryHeight: 基準（プライマリ）スクリーンの高さ
    /// - Returns: top-left 基準の Y（`primaryHeight - (originY + height)`）
    public static func flipY(originY: Double, height: Double, primaryHeight: Double) -> Double {
        primaryHeight - (originY + height)
    }

    /// bottom-left 原点の矩形を top-left 原点へ変換する（X・幅・高さは不変）。
    public static func flip(_ rect: Rect, primaryHeight: Double) -> Rect {
        Rect(
            x: rect.x,
            y: flipY(originY: rect.y, height: rect.height, primaryHeight: primaryHeight),
            width: rect.width,
            height: rect.height
        )
    }
}
