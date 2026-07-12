import XCTest
@testable import MacPilotVoice

final class STTClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testOpenAICompatibleRequestUsesAuthAndMultipartFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let body = try self.requestBody(request)
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(text.contains("name=\"model\""))
            XCTAssertTrue(text.contains("whisper-1"))
            XCTAssertTrue(text.contains("name=\"language\""))
            XCTAssertTrue(text.contains("zh"))
            XCTAssertTrue(text.contains("filename=\"recording.wav\""))
            return (200, Data(#"{"text":"你好世界"}"#.utf8))
        }
        let client = OpenAICompatibleSTT(
            configuration: try .preset(.openAIWhisper),
            apiKey: "secret",
            language: "zh",
            session: makeSession()
        )

        let result = try await client.transcribe(audio())

        XCTAssertEqual(result, "你好世界")
    }

    func testCustomEndpointNormalizationAndOptionalAuth() throws {
        let config = try STTProviderConfiguration.customWhisper(baseURL: "http://localhost:8000/v1/", model: "local-model")
        XCTAssertEqual(config.endpoint.absoluteString, "http://localhost:8000/v1/audio/transcriptions")
        XCTAssertFalse(config.apiKeyRequired)
    }

    func testHTTP401And429AreTyped() async {
        for (status, expected) in [(401, STTClientError.unauthorized), (429, STTClientError.rateLimited)] {
            MockURLProtocol.handler = { _ in (status, Data("error".utf8)) }
            let client = OpenAICompatibleSTT(configuration: try! .preset(.openAIWhisper), apiKey: "key", session: makeSession())
            do { _ = try await client.transcribe(audio()); XCTFail("Expected HTTP error") }
            catch { XCTAssertEqual(error as? STTClientError, expected) }
        }
    }

    func testTimeoutAndMalformedResponseAreTyped() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let timeoutClient = OpenAICompatibleSTT(configuration: try! .preset(.openAIWhisper), apiKey: "key", session: makeSession())
        do { _ = try await timeoutClient.transcribe(audio()); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? STTClientError, .timeout) }

        MockURLProtocol.handler = { _ in (200, Data(#"{"unexpected":true}"#.utf8)) }
        let malformedClient = OpenAICompatibleSTT(configuration: try! .preset(.openAIWhisper), apiKey: "key", session: makeSession())
        do { _ = try await malformedClient.transcribe(audio()); XCTFail("Expected malformed response") }
        catch { XCTAssertEqual(error as? STTClientError, .malformedResponse) }
    }

    func testKnownProviderDefaultsMatchLegacyApp() throws {
        XCTAssertEqual(try STTProviderConfiguration.preset(.glmASR).model, "glm-asr-2512")
        XCTAssertEqual(try STTProviderConfiguration.preset(.groqWhisper).model, "whisper-large-v3-turbo")
        XCTAssertEqual(try STTProviderConfiguration.preset(.siliconFlow).model, "FunAudioLLM/SenseVoiceSmall")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func audio() -> RecordedAudio {
        RecordedAudio(wavData: Data("RIFF-test".utf8), duration: 1)
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol {
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
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
