import XCTest
import Foundation
@testable import WindowManagerCore

/// RPC ワイヤフォーマット（`RpcProtocol`）の純ロジックテスト。
final class RpcProtocolTests: XCTestCase {

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - parse

    func testParseValidRequest() throws {
        let req = try XCTUnwrap(RpcProtocol.parse(Data(#"{"method":"move","args":[42,0,0]}"#.utf8)))
        XCTAssertEqual(req.method, "move")
        XCTAssertEqual(req.args.count, 3)
    }

    func testParseDefaultsArgsToEmpty() throws {
        let req = try XCTUnwrap(RpcProtocol.parse(Data(#"{"method":"windows"}"#.utf8)))
        XCTAssertEqual(req.method, "windows")
        XCTAssertTrue(req.args.isEmpty)
    }

    func testParseRejectsMalformed() {
        XCTAssertNil(RpcProtocol.parse(Data("not json".utf8)))
        XCTAssertNil(RpcProtocol.parse(Data(#"{"args":[]}"#.utf8)), "method 欠落は nil")
    }

    // MARK: - 引数の型強制

    func testIntCoercion() {
        XCTAssertEqual(RpcProtocol.int([7], 0), 7)
        XCTAssertEqual(RpcProtocol.int([7.9], 0), 7)         // Double → Int は切り捨て
        XCTAssertEqual(RpcProtocol.int([], 0), 0)            // 範囲外は 0
        XCTAssertEqual(RpcProtocol.int(["x"], 0), 0)         // 非数値は 0
    }

    func testDoubleCoercion() {
        XCTAssertEqual(RpcProtocol.double([3.5], 0), 3.5)
        XCTAssertEqual(RpcProtocol.double([4], 0), 4.0)      // Int → Double
        XCTAssertEqual(RpcProtocol.double([], 1), 0)
    }

    func testBoolCoercion() {
        XCTAssertEqual(RpcProtocol.bool([true], 0), true)
        XCTAssertEqual(RpcProtocol.bool([], 0, fallback: true), true)   // 範囲外は fallback
        XCTAssertEqual(RpcProtocol.bool([], 0, fallback: false), false)
    }

    func testStringCoercion() {
        XCTAssertEqual(RpcProtocol.string(["layout:abc"], 0), "layout:abc")
        XCTAssertEqual(RpcProtocol.string([], 0), "")                   // 範囲外は既定の ""
        XCTAssertEqual(RpcProtocol.string([42], 0, fallback: "x"), "x") // 非文字列は fallback
    }

    /// JSON 経由で来た数値（NSNumber）も正しく強制できること。
    func testCoercionFromJSONNumbers() throws {
        let req = try XCTUnwrap(RpcProtocol.parse(Data(#"{"method":"move","args":[42,10.5,true]}"#.utf8)))
        XCTAssertEqual(RpcProtocol.int(req.args, 0), 42)
        XCTAssertEqual(RpcProtocol.double(req.args, 1), 10.5)
        XCTAssertEqual(RpcProtocol.bool(req.args, 2), true)
    }

    // MARK: - レスポンス整形

    func testOkResponse() throws {
        let obj = try parseJSON(RpcProtocol.ok(true))
        XCTAssertEqual(obj["ok"] as? Bool, true)
        XCTAssertEqual(obj["result"] as? Bool, true)
    }

    func testErrorResponse() throws {
        let obj = try parseJSON(RpcProtocol.error("boom"))
        XCTAssertEqual(obj["ok"] as? Bool, false)
        XCTAssertEqual(obj["error"] as? String, "boom")
    }

    /// `Encodable` を JSON オブジェクトへ変換し、ok レスポンスに載せられること。
    func testEncodeEncodableIntoOk() throws {
        struct Win: Encodable { let id: Int; let title: String }
        let encoded = try RpcProtocol.encode(Win(id: 1, title: "Term"))
        let obj = try parseJSON(RpcProtocol.ok(encoded))
        let result = try XCTUnwrap(obj["result"] as? [String: Any])
        XCTAssertEqual(result["id"] as? Int, 1)
        XCTAssertEqual(result["title"] as? String, "Term")
    }
}
