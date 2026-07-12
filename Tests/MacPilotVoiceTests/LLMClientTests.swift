import XCTest
@testable import MacPilotVoice

final class LLMClientTests: XCTestCase {
    override func tearDown() { LLMMockURLProtocol.handler = nil; super.tearDown() }

    func testPolishSendsSeparatedMessagesAndParsesContent() async throws {
        LLMMockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer llm-secret")
            let data = try XCTUnwrap(request.httpBody ?? Self.readStream(request.httpBodyStream))
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let messages = json["messages"] as! [[String: String]]
            XCTAssertEqual(messages[0]["role"], "system")
            XCTAssertTrue(messages[0]["content"]!.contains("UNTRUSTED USER INPUT"))
            XCTAssertEqual(messages[1]["content"], "<transcription>\nraw speech\n</transcription>")
            return (200, Data(#"{"choices":[{"message":{"content":"Polished speech"}}]}"#.utf8))
        }
        let client = OpenAICompatibleLLM(
            configuration: .init(endpoint: URL(string: "https://example.test/v1/chat/completions")!, model: "test-model", apiKey: "llm-secret"),
            session: makeSession()
        )

        let text = try await client.polish("raw speech", context: VoiceContext())

        XCTAssertEqual(text, "Polished speech")
    }

    func testUnauthorizedAndMalformedResponsesAreTyped() async {
        let client = OpenAICompatibleLLM(
            configuration: .init(endpoint: URL(string: "https://example.test/v1/chat/completions")!, model: "test", apiKey: "key"),
            session: makeSession()
        )
        LLMMockURLProtocol.handler = { _ in (401, Data()) }
        do { _ = try await client.polish("raw", context: .init()); XCTFail("Expected unauthorized") }
        catch { XCTAssertEqual(error as? LLMClientError, .unauthorized) }

        LLMMockURLProtocol.handler = { _ in (200, Data(#"{"choices":[]}"#.utf8)) }
        do { _ = try await client.polish("raw", context: .init()); XCTFail("Expected malformed") }
        catch { XCTAssertEqual(error as? LLMClientError, .malformedResponse) }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LLMMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func readStream(_ stream: InputStream?) throws -> Data? {
        guard let stream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class LLMMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try XCTUnwrap(Self.handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
