import XCTest
@testable import WindowManagerCore

/// `SLPSPostEventRecordTo` へ渡すイベントレコードのバイト配置テスト。
///
/// このレコードは不透明なバイナリ構造体で、オフセットが 1 つでもずれると
/// 「フォーカスが移らない」という形で静かに壊れる。実機でしか気づけない不具合なので、
/// バイト配置だけは Apple のフレームワークに触れない純ロジックとして切り出し、
/// Linux 上の CI で固定しておく。
final class KeyWindowEventRecordTests: XCTestCase {

    func testRecordLength() {
        let record = KeyWindowEventRecord.make(windowID: 1, phase: .mouseDown)
        XCTAssertEqual(record.count, KeyWindowEventRecord.size)
        // レコードは自身の長さを申告する。バッファはそれより大きく確保して
        // 受け手が申告値を超えて読んでも配列外へ出ないようにする。
        XCTAssertEqual(record[KeyWindowEventRecord.lengthOffset], KeyWindowEventRecord.declaredLength)
        XCTAssertGreaterThanOrEqual(KeyWindowEventRecord.size, Int(KeyWindowEventRecord.declaredLength))
    }

    func testPhaseIsEncodedAtTypeOffset() {
        let down = KeyWindowEventRecord.make(windowID: 1, phase: .mouseDown)
        XCTAssertEqual(down[KeyWindowEventRecord.typeOffset], 0x01)

        let up = KeyWindowEventRecord.make(windowID: 1, phase: .mouseUp)
        XCTAssertEqual(up[KeyWindowEventRecord.typeOffset], 0x02)
    }

    /// 2 通目は 1 通目のバッファを使い回して種別だけ差し替える。
    /// そのとき他のフィールド（特に window id）が壊れないこと。
    func testSetPhaseKeepsEveryOtherByte() {
        var record = KeyWindowEventRecord.make(windowID: 0xDEADBEEF, phase: .mouseDown)
        let expected = KeyWindowEventRecord.make(windowID: 0xDEADBEEF, phase: .mouseUp)
        KeyWindowEventRecord.setPhase(.mouseUp, in: &record)
        XCTAssertEqual(record, expected)
    }

    func testWindowIDIsLittleEndian() {
        let record = KeyWindowEventRecord.make(windowID: 0x04030201, phase: .mouseDown)
        let offset = KeyWindowEventRecord.windowIDOffset
        XCTAssertEqual(Array(record[offset..<(offset + 4)]), [0x01, 0x02, 0x03, 0x04])
    }

    /// 座標は全ビット 1（= NaN）にして「コンテンツ外」を表す。
    /// ここが 0 だと (0,0) の実クリックとして解釈され、アプリ側の処理が発火してしまう。
    func testLocationIsFilledWithNaNPattern() {
        let record = KeyWindowEventRecord.make(windowID: 1, phase: .mouseDown)
        let offset = KeyWindowEventRecord.locationOffset
        let location = Array(record[offset..<(offset + KeyWindowEventRecord.locationSize)])
        XCTAssertEqual(location, [UInt8](repeating: 0xFF, count: KeyWindowEventRecord.locationSize))
    }

    func testKeyWindowFlagIsSet() {
        let record = KeyWindowEventRecord.make(windowID: 1, phase: .mouseDown)
        XCTAssertEqual(record[KeyWindowEventRecord.keyWindowFlagOffset], KeyWindowEventRecord.keyWindowFlag)
    }

    /// 上で検査したフィールド以外はすべて 0 のままであること
    /// （余計なバイトが立つと WindowServer に別の意味で解釈されうる）。
    func testAllOtherBytesAreZero() {
        let record = KeyWindowEventRecord.make(windowID: 0xFFFFFFFF, phase: .mouseDown)
        var touched = Set([
            KeyWindowEventRecord.lengthOffset,
            KeyWindowEventRecord.typeOffset,
            KeyWindowEventRecord.keyWindowFlagOffset
        ])
        for i in 0..<KeyWindowEventRecord.locationSize {
            touched.insert(KeyWindowEventRecord.locationOffset + i)
        }
        for i in 0..<4 {
            touched.insert(KeyWindowEventRecord.windowIDOffset + i)
        }
        for (index, byte) in record.enumerated() where !touched.contains(index) {
            XCTAssertEqual(byte, 0, "offset \(String(index, radix: 16)) が 0 でない")
        }
    }
}
