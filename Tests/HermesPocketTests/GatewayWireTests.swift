import Foundation
import Testing
@testable import HermesPocket

struct GatewayWireTests {
    @Test func decodesNewlineCoalescedFramesAndUnknownEvents() throws {
        let data = Data("""
        {"jsonrpc":"2.0","id":"rpc-1","result":{"revision":9007199254740993}}
        {"jsonrpc":"2.0","method":"event","params":{"type":"future.extension","payload":{"nested":[true,null,3.5]},"seq":8}}

        """.utf8)
        let frames = try GatewayEnvelope.decodeFrames(data)
        #expect(frames.count == 2)
        #expect(frames[0].result?["revision"].int == 9_007_199_254_740_993)
        #expect(frames[1].params?["type"].string == "future.extension")
        #expect(frames[1].params?["payload"]["nested"].array == [.bool(true), .null, .number(3.5)])
    }

    @Test func rpcErrorPreservesStructuredFenceFailure() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":"a","error":{"code":4001,"message":"stale revision","data":{"revision":9,"reason":"stale_revision"}}}"#.utf8)
        let frame = try #require(GatewayEnvelope.decodeFrames(data).first)
        #expect(frame.error?.code == 4001)
        #expect(frame.error?.data?["revision"].int == 9)
    }

    @Test func requestOmitsAbsentResponseFields() throws {
        let request = GatewayEnvelope(id: .string("rpc"), method: "prompt.submit", params: .object(["submission_id": .string("durable")]))
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(encoded["jsonrpc"].string == "2.0")
        #expect(encoded.object?["result"] == nil)
        #expect(encoded.object?["error"] == nil)
        #expect(encoded["params"]["submission_id"].string == "durable")
    }

    @Test func malformedFrameIsRejected() {
        #expect(throws: (any Error).self) { try GatewayEnvelope.decodeFrames(Data("not json".utf8)) }
    }
}
