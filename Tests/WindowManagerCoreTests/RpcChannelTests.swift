import XCTest
import Foundation
@testable import WindowManagerCore

/// RPC フレーミング層（`RpcChannel`）のテスト。
/// ディスパッチャを注入できるため macOS API なしで Linux 上でも検証できる。
final class RpcChannelTests: XCTestCase {

    /// テスト用の純ロジックなディスパッチャ（macOS には一切触れない）。
    private func makeChannel() -> RpcChannel {
        RpcChannel { data in
            guard let req = RpcProtocol.parse(data) else {
                return RpcProtocol.error("malformed request")
            }
            switch req.method {
            case "add":
                return RpcProtocol.ok(RpcProtocol.double(req.args, 0) + RpcProtocol.double(req.args, 1))
            case "echo":
                return RpcProtocol.ok(req.args)
            default:
                return RpcProtocol.error("unknown method: \(req.method)")
            }
        }
    }

    private func line(_ s: String) -> Data { Data(s.utf8) + Data([0x0A]) }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 改行区切りで 1 リクエストが揃ったら、改行終端の応答が 1 つ得られること。
    func testFramingProducesOneNewlineTerminatedResponse() throws {
        let channel = makeChannel()
        channel.appendRequest(line(#"{"method":"add","args":[2,3]}"#))

        let out = channel.dequeueResponse(max: 4096)
        XCTAssertEqual(out.last, 0x0A, "応答は改行終端であること")

        let obj = try parseJSON(out.dropLast())
        XCTAssertEqual(obj["ok"] as? Bool, true)
        XCTAssertEqual(obj["result"] as? Double, 5)
    }

    /// 改行未到達の部分 write では応答が生成されず、リクエストが保留されること。
    func testPartialRequestBuffersUntilNewline() {
        let channel = makeChannel()
        channel.appendRequest(Data(#"{"method":"add","#.utf8))
        XCTAssertTrue(channel.dequeueResponse(max: 4096).isEmpty)
        XCTAssertTrue(channel.hasPendingRequest)

        channel.appendRequest(Data(#""args":[1,1]}"#.utf8) + Data([0x0A]))
        XCTAssertFalse(channel.dequeueResponse(max: 4096).isEmpty)
        XCTAssertFalse(channel.hasPendingRequest)
    }

    /// 1 回の write に複数行が含まれる場合、応答も行数分まとめてバッファされること。
    func testMultipleRequestsInSingleWrite() throws {
        let channel = makeChannel()
        channel.appendRequest(line(#"{"method":"add","args":[1,2]}"#) + line(#"{"method":"add","args":[3,4]}"#))

        let out = channel.dequeueResponse(max: 4096)
        let lines = out.split(separator: 0x0A)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(try parseJSON(Data(lines[0]))["result"] as? Double, 3)
        XCTAssertEqual(try parseJSON(Data(lines[1]))["result"] as? Double, 7)
    }

    /// 未知メソッドはエラー応答（ok=false）になること。
    func testUnknownMethodReturnsError() throws {
        let channel = makeChannel()
        channel.appendRequest(line(#"{"method":"nope","args":[]}"#))
        let obj = try parseJSON(channel.dequeueResponse(max: 4096).dropLast())
        XCTAssertEqual(obj["ok"] as? Bool, false)
        XCTAssertNotNil(obj["error"])
    }

    /// 空行（連続改行）はスキップされ、応答を生成しないこと。
    func testEmptyLinesAreSkipped() {
        let channel = makeChannel()
        channel.appendRequest(Data([0x0A, 0x0A]))
        XCTAssertTrue(channel.dequeueResponse(max: 4096).isEmpty)
    }

    /// dequeue は `max` バイトで分割払い出しでき、残りは次回に持ち越されること。
    func testDequeueRespectsMax() throws {
        let channel = makeChannel()
        channel.appendRequest(line(#"{"method":"add","args":[2,3]}"#))
        let full = channel.dequeueResponse(max: 4096)

        let channel2 = makeChannel()
        channel2.appendRequest(line(#"{"method":"add","args":[2,3]}"#))
        var assembled = Data()
        while true {
            let chunk = channel2.dequeueResponse(max: 3)
            if chunk.isEmpty { break }
            XCTAssertLessThanOrEqual(chunk.count, 3)
            assembled.append(chunk)
        }
        XCTAssertEqual(assembled, full)
    }
}
