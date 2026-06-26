import Foundation

/// Ruby → Swift RPC の同期チャネル（プラットフォーム非依存）。
///
/// `fd_write` で積まれた生バイトを改行区切りでフレーミングし、1 リクエストが
/// 揃うたびに注入された `dispatcher` を同期実行、応答を `fd_read` 用にバッファする。
/// 単一スレッド・同期前提のためロック不要。
///
/// 実際の macOS API へのディスパッチは `dispatcher` クロージャに切り出してあるため、
/// このフレーミング層は Apple フレームワークに依存せず Linux 上でテストできる。
public final class RpcChannel {

    /// 1 リクエスト（改行を含まない 1 行）を処理して 1 レスポンスを返す関数。
    public typealias Dispatcher = (Data) -> Data

    private var requestBuffer = Data()
    private var responseBuffer = Data()
    private let dispatcher: Dispatcher

    public init(dispatcher: @escaping Dispatcher) {
        self.dispatcher = dispatcher
    }

    /// `fd_write` された生バイトを受け取り、改行で 1 リクエストが揃ったら処理する。
    /// 空行（連続改行）はスキップする。
    public func appendRequest(_ bytes: Data) {
        requestBuffer.append(bytes)
        while let nl = requestBuffer.firstIndex(of: 0x0A) {
            let line = requestBuffer[requestBuffer.startIndex..<nl]
            requestBuffer.removeSubrange(requestBuffer.startIndex...nl)
            if line.isEmpty { continue }
            var response = dispatcher(Data(line))
            response.append(0x0A) // Ruby 側は行単位で read する
            responseBuffer.append(response)
        }
    }

    /// `fd_read` 要求に対して、バッファ済み応答から最大 `max` バイト払い出す。
    public func dequeueResponse(max: Int) -> Data {
        let n = Swift.min(max, responseBuffer.count)
        let chunk = responseBuffer.prefix(n)
        responseBuffer.removeFirst(n)
        return Data(chunk)
    }

    /// 未処理（改行待ち）リクエストが残っているか。テスト・診断用。
    public var hasPendingRequest: Bool { !requestBuffer.isEmpty }
}
