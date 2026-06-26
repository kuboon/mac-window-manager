import XCTest
@testable import WindowManager

final class RpcChannelTests: XCTestCase {

    /// 改行区切りで 1 リクエストが揃ったら応答が 1 行バッファされること。
    func testFramingProducesOneLineResponse() throws {
        let channel = RpcChannel()
        // 未知メソッドは macOS API に触れずエラー応答を返すのでフレーミング検証に好適。
        let request = Data(#"{"method":"__ping__","args":[]}"#.utf8) + Data([0x0A])
        channel.appendRequest(request)

        let out = channel.dequeueResponse(max: 4096)
        XCTAssertTrue(out.last == 0x0A, "応答は改行終端であること")

        let obj = try JSONSerialization.jsonObject(with: out.dropLast()) as? [String: Any]
        XCTAssertEqual(obj?["ok"] as? Bool, false)
        XCTAssertNotNil(obj?["error"])
    }

    /// 部分的な write（改行未到達）では応答が生成されないこと。
    func testPartialRequestBuffersUntilNewline() {
        let channel = RpcChannel()
        channel.appendRequest(Data(#"{"method":"__ping__","#.utf8))
        XCTAssertTrue(channel.dequeueResponse(max: 4096).isEmpty)

        channel.appendRequest(Data(#""args":[]}"#.utf8) + Data([0x0A]))
        XCTAssertFalse(channel.dequeueResponse(max: 4096).isEmpty)
    }
}
