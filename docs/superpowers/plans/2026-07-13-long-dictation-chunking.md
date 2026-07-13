# Long Dictation Chunking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support up to 12 minutes of native MacPilot dictation by splitting GLM-ASR audio into ordered 28-second transcription requests.

**Architecture:** Add a pure PCM16 WAV segmenter, then let `OpenAICompatibleSTT` apply provider-specific request segmentation and per-segment retry while keeping `VoicePipeline` unaware of request count. Decouple the 720-second capture limit from the 28-second provider limit, and use a small tested deadline state to make `VoiceStore` auto-stop exactly once.

**Tech Stack:** Swift 5.7, Foundation `URLSession`, AVFoundation, XCTest, Swift Package Manager.

---

## File map

- Create `native-macos/Sources/MacPilotVoice/PCM16WAVSegmenter.swift`: parse and split PCM16 mono WAV data.
- Create `native-macos/Tests/MacPilotVoiceTests/WAVSegmenterTests.swift`: segment integrity tests.
- Modify `native-macos/Sources/MacPilotVoice/STT/OpenAICompatibleSTT.swift`: request limit, ordered segment transcription, retry.
- Modify `native-macos/Tests/MacPilotVoiceTests/STTClientTests.swift`: multipart ordering and retry tests.
- Create `native-macos/Sources/MacPilotVoice/RecordingDeadline.swift`: one-shot 720-second deadline state.
- Create `native-macos/Tests/MacPilotVoiceTests/RecordingDeadlineTests.swift`: deadline behavior.
- Modify `native-macos/Sources/MacPilotApp/VoiceStore.swift`: 12-minute capture, auto-stop, readable errors.

### Task 1: Split valid PCM16 WAV recordings

**Files:**
- Create: `native-macos/Sources/MacPilotVoice/PCM16WAVSegmenter.swift`
- Create: `native-macos/Tests/MacPilotVoiceTests/WAVSegmenterTests.swift`

- [ ] **Step 1: Write failing segment tests**

Create WAV fixtures through `PCM16WAVEncoder` and assert that 27 seconds stays one segment, 28 seconds stays one segment, and 60 seconds becomes durations `[28, 28, 4]`. Parse each returned data chunk and assert RIFF/WAVE markers, 16 kHz mono PCM16 format, and total PCM byte equality.

```swift
func testSixtySecondsSplitsIntoTwoFullPartsAndRemainder() throws {
    let wav = try makeWAV(seconds: 60)
    let segments = try PCM16WAVSegmenter.split(wav, maximumDuration: 28)
    XCTAssertEqual(segments.map { $0.duration }, [28, 28, 4])
    XCTAssertEqual(segments.reduce(0) { $0 + Int(readUInt32($1.wavData, at: 40)) }, 60 * 16_000 * 2)
}
```

- [ ] **Step 2: Verify RED**

Run: `cd native-macos && swift test --filter WAVSegmenterTests`

Expected: compilation failure because `PCM16WAVSegmenter` does not exist.

- [ ] **Step 3: Implement the pure segmenter**

Expose:

```swift
public enum PCM16WAVSegmenter {
    public static func split(_ wavData: Data, maximumDuration: TimeInterval) throws -> [RecordedAudio]
}
```

Validate RIFF/WAVE, PCM format 1, mono channel count, 16-bit samples, positive sample rate, and a bounded `data` chunk. Split PCM on two-byte sample boundaries and rebuild every WAV with `PCM16WAVEncoder.makeWAV(pcmData:sampleRate:)`, extracted from the existing encoder.

- [ ] **Step 4: Verify GREEN**

Run: `cd native-macos && swift test --filter WAVSegmenterTests`

Expected: all segmenter tests pass.

- [ ] **Step 5: Commit**

```bash
git add native-macos/Sources/MacPilotVoice/PCM16WAVEncoder.swift native-macos/Sources/MacPilotVoice/PCM16WAVSegmenter.swift native-macos/Tests/MacPilotVoiceTests/WAVSegmenterTests.swift
git commit -m "feat: split long PCM recordings into WAV segments"
```

### Task 2: Transcribe GLM segments in order with retry

**Files:**
- Modify: `native-macos/Sources/MacPilotVoice/STT/OpenAICompatibleSTT.swift`
- Modify: `native-macos/Tests/MacPilotVoiceTests/STTClientTests.swift`

- [ ] **Step 1: Write failing request tests**

Generate a 60-second WAV, return `part 1`, `part 2`, and `part 3` from successive mock requests, and assert the result is `part 1 part 2 part 3`, filenames are ordered, and there are three requests. Add tests proving OpenAI sends the same long fixture once, a GLM 500 response retries three total attempts, and a 401 performs one attempt.

```swift
func testGLMTranscribesLongRecordingAsOrderedSegments() async throws {
    var filenames: [String] = []
    MockURLProtocol.handler = { request in
        let body = try self.requestBody(request)
        let filename = try XCTUnwrap(self.multipartFilename(body))
        filenames.append(filename)
        return (200, Data(#"{"text":"part \#(filenames.count)"}"#.utf8))
    }
    let result = try await glmClient().transcribe(longAudio(seconds: 60))
    XCTAssertEqual(result, "part 1 part 2 part 3")
    XCTAssertEqual(filenames, ["audio_part_1.wav", "audio_part_2.wav", "audio_part_3.wav"])
}
```

- [ ] **Step 2: Verify RED**

Run: `cd native-macos && swift test --filter STTClientTests`

Expected: the long GLM test fails because the client rejects recordings over 28 seconds.

- [ ] **Step 3: Implement segmented transcription**

Rename configuration semantics to `maximumRequestDuration`. Split only when it is non-nil, call a private `transcribeSegment(_:fileName:)` sequentially, trim non-empty text, and join with one space. Keep `recording.wav` for the single-request path and use `audio_part_N.wav` for multiple segments.

- [ ] **Step 4: Implement finite retry**

Wrap each request in at most three attempts. Retry `STTClientError.timeout`, `.rateLimited`, and `.httpStatus(500...599)`; do not retry authorization, malformed responses, empty transcripts, invalid configuration, or other status codes. Check task cancellation before every attempt and segment.

- [ ] **Step 5: Verify GREEN**

Run: `cd native-macos && swift test --filter STTClientTests`

Expected: all STT client tests pass.

- [ ] **Step 6: Commit**

```bash
git add native-macos/Sources/MacPilotVoice/STT/OpenAICompatibleSTT.swift native-macos/Tests/MacPilotVoiceTests/STTClientTests.swift
git commit -m "feat: transcribe long GLM recordings in chunks"
```

### Task 3: Enforce the 12-minute session limit once

**Files:**
- Create: `native-macos/Sources/MacPilotVoice/RecordingDeadline.swift`
- Create: `native-macos/Tests/MacPilotVoiceTests/RecordingDeadlineTests.swift`
- Modify: `native-macos/Sources/MacPilotApp/VoiceStore.swift`

- [ ] **Step 1: Write failing deadline tests**

```swift
func testDeadlineTriggersOnlyOnceAtTwelveMinutes() {
    var deadline = RecordingDeadline(limit: 720)
    XCTAssertFalse(deadline.consume(elapsed: 719.9))
    XCTAssertTrue(deadline.consume(elapsed: 720))
    XCTAssertFalse(deadline.consume(elapsed: 721))
    deadline.reset()
    XCTAssertTrue(deadline.consume(elapsed: 720))
}
```

- [ ] **Step 2: Verify RED**

Run: `cd native-macos && swift test --filter RecordingDeadlineTests`

Expected: compilation failure because `RecordingDeadline` does not exist.

- [ ] **Step 3: Implement deadline state and wire VoiceStore**

Add `RecordingDeadline(limit: 720)` with one-shot `consume(elapsed:)` and `reset()`. Build `AVAudioCapture(maximumDuration: 720)`. Reset the deadline when recording starts; in the 100 ms timer, update the capsule, call `perform(.stopRecording)` once when `consume` returns true, and exit the timer loop.

- [ ] **Step 4: Map audio errors**

Extend `VoiceStore.describe`:

```swift
case AudioCaptureError.maximumDurationExceeded:
    return "单次录音最长 12 分钟。"
case AudioCaptureError.emptyRecording:
    return "没有录到有效声音，请重试。"
case AudioCaptureError.invalidFormat, AudioCaptureError.engineUnavailable:
    return "无法使用当前麦克风录音，请检查输入设备后重试。"
```

- [ ] **Step 5: Verify focused and full tests**

Run: `cd native-macos && swift test --filter RecordingDeadlineTests && swift test`

Expected: deadline tests and the complete native suite pass.

- [ ] **Step 6: Commit**

```bash
git add native-macos/Sources/MacPilotVoice/RecordingDeadline.swift native-macos/Tests/MacPilotVoiceTests/RecordingDeadlineTests.swift native-macos/Sources/MacPilotApp/VoiceStore.swift
git commit -m "feat: auto-stop dictation at twelve minutes"
```

### Task 4: Release verification and installation

**Files:**
- Modify only if verification reveals a defect in planned files.

- [ ] **Step 1: Check the final diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors and only planned changes before commits.

- [ ] **Step 2: Run all native tests and release build**

Run: `cd native-macos && swift test && swift build -c release`

Expected: all tests pass and release build succeeds.

- [ ] **Step 3: Build, sign, and install the app**

Run: `cd native-macos && bash scripts/build-app.sh && codesign --verify --deep --strict build/MacPilot.app && pkill -x MacPilotApp || true && rm -rf /Applications/MacPilot.app && ditto build/MacPilot.app /Applications/MacPilot.app && open /Applications/MacPilot.app`

Expected: the bundle verifies, the installed binary matches the built binary, and one `MacPilotApp` process starts.
