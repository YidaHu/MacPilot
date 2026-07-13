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

    func testGLMTranscribesLongRecordingAsOrderedSegments() async throws {
        var filenames: [String] = []
        MockURLProtocol.handler = { request in
            let body = try self.requestBody(request)
            filenames.append(try self.multipartFilename(body))
            return (200, Data(#"{"text":"part \#(filenames.count)"}"#.utf8))
        }
        let client = OpenAICompatibleSTT(
            configuration: try .preset(.glmASR),
            apiKey: "key",
            session: makeSession()
        )

        let result = try await client.transcribe(longAudio(seconds: 60))

        XCTAssertEqual(result, "part 1 part 2 part 3")
        XCTAssertEqual(filenames, ["audio_part_1.wav", "audio_part_2.wav", "audio_part_3.wav"])
    }

    func testProviderWithoutRequestLimitSendsLongRecordingOnce() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { _ in
            requestCount += 1
            return (200, Data(#"{"text":"one request"}"#.utf8))
        }
        let client = OpenAICompatibleSTT(
            configuration: try .preset(.openAIWhisper),
            apiKey: "key",
            session: makeSession()
        )

        let result = try await client.transcribe(longAudio(seconds: 60))

        XCTAssertEqual(result, "one request")
        XCTAssertEqual(requestCount, 1)
    }

    func testServerFailureRetriesAChunkAtMostThreeTimes() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { _ in
            requestCount += 1
            if requestCount < 3 { return (500, Data("error".utf8)) }
            return (200, Data(#"{"text":"recovered"}"#.utf8))
        }
        let client = OpenAICompatibleSTT(
            configuration: try .preset(.glmASR),
            apiKey: "key",
            session: makeSession()
        )

        let result = try await client.transcribe(longAudio(seconds: 1))

        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(requestCount, 3)
    }

    func testUnauthorizedResponseIsNotRetried() async {
        var requestCount = 0
        MockURLProtocol.handler = { _ in
            requestCount += 1
            return (401, Data("error".utf8))
        }
        let client = OpenAICompatibleSTT(
            configuration: try! .preset(.glmASR),
            apiKey: "key",
            session: makeSession()
        )

        do {
            _ = try await client.transcribe(longAudio(seconds: 1))
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? STTClientError, .unauthorized)
            XCTAssertEqual(requestCount, 1)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func audio() -> RecordedAudio {
        RecordedAudio(wavData: Data("RIFF-test".utf8), duration: 1)
    }

    private func longAudio(seconds: Int) -> RecordedAudio {
        let pcm = Data(repeating: 0x2a, count: seconds * 16_000 * 2)
        var wav = Data("RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &wav)
        wav.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt32(16_000), to: &wav)
        append(UInt32(32_000), to: &wav)
        append(UInt16(2), to: &wav)
        append(UInt16(16), to: &wav)
        wav.append(Data("data".utf8))
        append(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return RecordedAudio(wavData: wav, duration: TimeInterval(seconds))
    }

    private func multipartFilename(_ body: Data) throws -> String {
        let text = String(decoding: body, as: UTF8.self)
        let prefix = "filename=\""
        let start = try XCTUnwrap(text.range(of: prefix)?.upperBound)
        let end = try XCTUnwrap(text[start...].firstIndex(of: "\""))
        return String(text[start..<end])
    }

    private func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8(value >> 24))
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
