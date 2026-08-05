/// `SLPSPostEventRecordTo` へ渡す「合成マウスイベントレコード」のバイト列を組み立てる純ロジック。
///
/// macOS には「アプリを前面化しつつ、そのアプリの**特定のウィンドウ**をキーウィンドウにする」
/// 公開 API が無い。`AXUIElementPerformAction(win, kAXRaiseAction)` は前面化のみで、
/// キーウィンドウの選択はアプリ側の裁量に委ねられるため、複数ウィンドウを持つアプリでは
/// 「アプリは前に来たが、狙ったウィンドウにフォーカスが入らない」という取りこぼしが起きる。
///
/// yabai を筆頭とする既存のウィンドウマネージャは、private な `SLPSPostEventRecordTo` に
/// **座標がウィンドウ外（NaN）のマウス押下/離上イベント**を直接流し込むことでこれを解決している。
/// WindowServer は「そのウィンドウがクリックされた」と解釈してキーウィンドウを切り替えるが、
/// 座標が実コンテンツ上に無いためアプリ側のクリック処理は発火しない。
///
/// レコードは不透明なバイナリ構造体で、必要なフィールドのオフセットだけが経験的に知られている。
/// ここではその**バイト配置だけ**を扱う（Apple のフレームワークに触らないので Linux でもテスト可能）。
/// 実際の送信は macOS 側の `PrivateAPI.focusWindow` が行う。
public enum KeyWindowEventRecord {

    /// イベントの種別（オフセット `typeOffset` に置く値）。
    public enum Phase: UInt8 {
        case mouseDown = 0x01
        case mouseUp = 0x02
    }

    /// 確保するバッファ長。レコードが自己申告する長さ（`declaredLength`）より少し大きく取る。
    /// 受け手が申告値を超えて読んだ場合でも Swift の配列外へはみ出さないようにするための余白。
    public static let size = 0x100

    /// レコードが自己申告する長さ。
    public static let declaredLength: UInt8 = 0xF8

    static let lengthOffset = 0x04
    static let typeOffset = 0x08
    /// イベント座標（2 つの double）。全ビット 1 = NaN にして「コンテンツ外」を表す。
    static let locationOffset = 0x20
    static let locationSize = 0x10
    /// 「キーウィンドウを切り替える」ことを示すフラグ。
    static let keyWindowFlagOffset = 0x3A
    static let keyWindowFlag: UInt8 = 0x10
    /// 対象の CGWindowID（リトルエンディアン 4 バイト）。
    static let windowIDOffset = 0x3C

    /// 指定ウィンドウをキーウィンドウにするためのレコードを 1 つ組み立てる。
    ///
    /// 実際のフォーカス操作では `.mouseDown` → `.mouseUp` の 2 通を続けて送る
    /// （押しっぱなしのまま残すとドラッグ中と解釈されうるため）。
    public static func make(windowID: UInt32, phase: Phase) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        bytes[lengthOffset] = declaredLength
        bytes[typeOffset] = phase.rawValue
        bytes[keyWindowFlagOffset] = keyWindowFlag
        for i in 0..<locationSize {
            bytes[locationOffset + i] = 0xFF
        }
        withUnsafeBytes(of: windowID.littleEndian) { raw in
            for (i, byte) in raw.enumerated() {
                bytes[windowIDOffset + i] = byte
            }
        }
        return bytes
    }

    /// 既存のレコードの種別だけを差し替える（同じバッファを使い回して 2 通送るため）。
    public static func setPhase(_ phase: Phase, in bytes: inout [UInt8]) {
        precondition(bytes.count > typeOffset, "record too short")
        bytes[typeOffset] = phase.rawValue
    }
}
