import AVFoundation
import Foundation
import Security

/// Only the provider choice is stored in UserDefaults. Credentials stay in Keychain.
enum VoiceSearchProvider: String, CaseIterable, Identifiable {
    case apple, deepgram
    static let settingsKey = "destinationSpeechProvider"
    var id: String { rawValue }
    var title: String { self == .apple ? "Apple Speech" : "Deepgram" }
    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: settingsKey) ?? "") ?? .apple
    }
}

enum DeepgramKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "tandem.deepgram-experiment.speech",
         kSecAttrAccount as String: "deepgram-api-key"]
    }
    static func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeyError.unavailable }
        return key
    }
    static func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { throw KeyError.invalid }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeyError.unavailable }
        } else if status != errSecSuccess { throw KeyError.unavailable }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.unavailable }
    }
    enum KeyError: LocalizedError {
        case unavailable, invalid
        var errorDescription: String? {
            switch self {
            case .unavailable: "Couldn't access the API key in Keychain. Unlock the iPhone and try again."
            case .invalid: "Enter an API key without spaces or line breaks."
            }
        }
    }
}

/// Used only on the audio tap's serial callback. Converts immediately, before AVAudioEngine
/// reuses its buffer. The bounded stream keeps a slow network from accumulating audio.
nonisolated final class DeepgramAudioEncoder {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    let packets: AsyncThrowingStream<Data, Error>

    init(input: AVAudioFormat) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw StreamError.audio
        }
        self.output = output
        self.converter = converter
        let stream = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        packets = stream.stream
        continuation = stream.continuation
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * output.sampleRate / buffer.format.sampleRate)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            continuation.finish(throwing: StreamError.audio)
            return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error else {
            continuation.finish(throwing: StreamError.audio)
            return
        }
        guard converted.frameLength > 0, let samples = converted.int16ChannelData?[0] else { return }
        let result = continuation.yield(Data(bytes: samples, count: Int(converted.frameLength) * 2))
        if case .dropped = result { continuation.finish(throwing: StreamError.slowNetwork) }
    }

    enum StreamError: LocalizedError {
        case audio, slowNetwork
        var errorDescription: String? {
            switch self {
            case .audio: "Couldn't prepare microphone audio. Try again or use Apple Speech."
            case .slowNetwork: "The connection is too slow for voice search. Try again or use Apple Speech."
            }
        }
    }
}

/// A single short search session. No audio, transcripts, or credentials are logged or saved.
@MainActor
final class DeepgramSpeech {
    var onText: ((String) -> Void)?
    var onComplete: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private var sender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var committed = ""
    private var active = true
    private var finishing = false
    private var encoder: DeepgramAudioEncoder?

    init(key: String) {
        // English destination search for this experiment; matches the existing examples.
        let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&language=en&encoding=linear16&sample_rate=16000&channels=1&interim_results=true&punctuate=false&endpointing=1500")!
        var request = URLRequest(url: url)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
        socket = session.webSocketTask(with: request)
    }

    func start(encoder: DeepgramAudioEncoder) {
        self.encoder = encoder
        socket.resume()
        receiver = Task { [weak self] in
            guard let self else { return }
            do {
                while self.active {
                    let message = try await self.socket.receive()
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    let result = try JSONDecoder().decode(Response.self, from: data)
                    if result.type == "Error" { self.fail("Deepgram rejected the request. Check the API key and account, then retry."); return }
                    if result.type == "Metadata", self.finishing { self.complete(); return }
                    guard result.type == "Results" else { continue }
                    let words = result.channel?.alternatives.first?.transcript ?? ""
                    if result.is_final == true, !words.isEmpty {
                        self.committed = [self.committed, words].filter { !$0.isEmpty }.joined(separator: " ")
                    }
                    let text = result.is_final == true ? self.committed
                        : [self.committed, words].filter { !$0.isEmpty }.joined(separator: " ")
                    if !text.isEmpty { self.onText?(text) }
                    // CloseStream drains all queued audio; Metadata signals its final response.
                }
            } catch { self.networkFailure(error) }
        }
        sender = Task { [weak self] in
            guard let self else { return }
            do {
                for try await packet in encoder.packets {
                    try Task.checkCancellation()
                    try await self.socket.send(.data(packet))
                }
                guard self.active, self.finishing else { return }
                try await self.socket.send(.string("{\"type\":\"CloseStream\"}"))
            } catch { self.networkFailure(error) }
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.fail("Deepgram took too long. Try again or use Apple Speech.")
        }
    }

    func finish() {
        guard active, !finishing else { return }
        finishing = true
        encoder?.continuation.finish()
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.fail("Deepgram didn't finish the transcript. Try again or use Apple Speech.")
        }
    }

    func cancel() {
        active = false
        encoder?.continuation.finish()
        encoder = nil
        sender?.cancel()
        receiver?.cancel()
        deadline?.cancel()
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    private func complete() {
        guard active else { return }
        let words = committed
        cancel()
        onComplete?(words)
    }
    private func fail(_ detail: String) {
        guard active else { return }
        cancel()
        onError?(detail)
    }
    private func networkFailure(_ error: Error) {
        guard active else { return }
        if let error = error as? DeepgramAudioEncoder.StreamError {
            fail(error.localizedDescription)
        } else {
            // Never display raw network errors, which may contain request details.
            let status = (socket.response as? HTTPURLResponse)?.statusCode
            if status == 401 || status == 403 {
                fail("Deepgram couldn't authorize this key. Check the key and its permissions in Settings, then retry.")
            } else {
                fail("Couldn't connect to Deepgram or the connection was lost. Check your internet and API key, then retry or use Apple Speech.")
            }
        }
    }
    nonisolated private struct Response: Decodable {
        let type: String
        var is_final: Bool?
        var channel: Channel?
        struct Channel: Decodable {
            let alternatives: [Alternative]
        }
        struct Alternative: Decodable { let transcript: String }
    }
}
