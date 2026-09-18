import Foundation
import Testing

@testable import YouTubeKit

/// A scripted Google: device flow, token refresh and a resumable upload with one dropped chunk.
final class MockGoogle: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var state = State()
    static let lock = NSLock()

    struct State {
        var tokenPolls = 0
        var pendingPolls = 2
        var received = Data()
        var chunkRanges: [String] = []
        var failChunkAtOffset: Int?
        var failed = false
        var statusQueries = 0
        var refreshes = 0
        var totalBytes = 0
        var uploadStarted = false
        var lastMetadata: [String: Any] = [:]
    }

    static func reset() {
        lock.lock()
        state = State()
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "mock.google" }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        let reply = Self.respond(to: request, state: &Self.state)
        let (status, headers, body) = (reply.status, reply.headers, reply.body)
        Self.lock.unlock()
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func json(_ object: Any) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 65536)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    struct Reply {
        let status: Int
        let headers: [String: String]
        let body: Data
        init(_ status: Int, _ headers: [String: String] = [:], _ body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    static func respond(to request: URLRequest, state: inout State) -> Reply {
        let path = request.url?.path ?? ""
        let form = String(bytes: body(of: request), encoding: .utf8) ?? ""
        switch path {
        case "/device/code":
            return Reply(
                200, [:],
                json([
                    "device_code": "DEV123", "user_code": "ABCD-EFGH",
                    "verification_url": "https://www.google.com/device",
                    "interval": 1, "expires_in": 600,
                ])
            )
        case "/token":
            if form.contains("grant_type=refresh_token") {
                state.refreshes += 1
                return Reply(200, [:], json(["access_token": "fresh-token", "expires_in": 3600]))
            }
            state.tokenPolls += 1
            if state.tokenPolls <= state.pendingPolls {
                return Reply(428, [:], json(["error": "authorization_pending"]))
            }
            return Reply(
                200, [:], json(["access_token": "first-token", "refresh_token": "refresh-1", "expires_in": 3600]))
        case "/upload/youtube/v3/videos":
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token" else {
                return Reply(401, [:], json(["error": "unauthorised"]))
            }
            state.uploadStarted = true
            state.totalBytes = Int(request.value(forHTTPHeaderField: "X-Upload-Content-Length") ?? "0") ?? 0
            state.lastMetadata = (try? JSONSerialization.jsonObject(with: body(of: request)) as? [String: Any]) ?? [:]
            return Reply(200, ["Location": "https://mock.google/upload/session/XYZ"], Data())
        case "/upload/session/XYZ":
            let range = request.value(forHTTPHeaderField: "Content-Range") ?? ""
            if range.hasPrefix("bytes */") {
                state.statusQueries += 1
                return Reply(308, ["Range": "bytes=0-\(state.received.count - 1)"], Data())
            }
            state.chunkRanges.append(range)
            let parts = range.dropFirst("bytes ".count).split(separator: "/")
            let bounds = parts[0].split(separator: "-").compactMap { Int($0) }
            let chunk = body(of: request)
            if let fail = state.failChunkAtOffset, !state.failed, bounds[0] == fail {
                state.failed = true
                // Pretend half the chunk arrived before the connection dropped.
                state.received.append(chunk.prefix(chunk.count / 2))
                return Reply(503, [:], Data())
            }
            guard bounds[0] == state.received.count else {
                return Reply(400, [:], json(["error": "chunk out of order at \(bounds[0]) vs \(state.received.count)"]))
            }
            state.received.append(chunk)
            if state.received.count >= state.totalBytes {
                return Reply(200, [:], json(["id": "vid-42"]))
            }
            return Reply(308, ["Range": "bytes=0-\(state.received.count - 1)"], Data())
        default:
            return Reply(404, [:], Data())
        }
    }
}

@Suite("YouTube client", .serialized)
struct YouTubeKitTests {
    static let endpoints = YouTubeEndpoints(
        deviceCode: URL(string: "https://mock.google/device/code")!, token: URL(string: "https://mock.google/token")!,
        upload: URL(string: "https://mock.google/upload/youtube/v3/videos")!)

    static func client(store: InMemoryTokenStore) -> YouTubeClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGoogle.self]
        return YouTubeClient(
            credentials: YouTubeCredentials(clientID: "id", clientSecret: "secret"), store: store,
            session: URLSession(configuration: configuration), endpoints: endpoints, sleeper: { _ in })
    }

    @Test func deviceFlowPollsUntilApproved() async throws {
        MockGoogle.reset()
        let store = InMemoryTokenStore()
        let client = Self.client(store: store)
        let authorization = try await client.startDeviceAuthorization()
        #expect(authorization.userCode == "ABCD-EFGH")
        #expect(authorization.verificationURL.host == "www.google.com")
        let token = try await client.waitForAuthorization(authorization)
        #expect(token.accessToken == "first-token" && token.refreshToken == "refresh-1")
        #expect(MockGoogle.state.tokenPolls == 3)
        #expect(try store.load() == token)
        #expect(client.isSignedIn)
        try client.signOut()
        #expect(!client.isSignedIn)
    }

    @Test func missingCredentialsAreRejected() async {
        let client = YouTubeClient(
            credentials: YouTubeCredentials(clientID: "", clientSecret: ""), store: InMemoryTokenStore())
        await #expect(throws: YouTubeError.missingCredentials) { try await client.startDeviceAuthorization() }
        await #expect(throws: YouTubeError.notSignedIn) { try await client.validToken() }
    }

    @Test func uploadRefreshesTheTokenResumesAfterAFailureAndDeliversEveryByte() async throws {
        MockGoogle.reset()
        MockGoogle.state.failChunkAtOffset = 2 << 20
        let file = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString).mp4")
        var payload = Data(count: 5 << 20 + 12345)
        for index in stride(from: 0, to: payload.count, by: 4099) { payload[index] = UInt8(index % 251) }
        try payload.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let expired = OAuthToken(
            accessToken: "old", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(-10))
        let client = Self.client(store: InMemoryTokenStore(token: expired))
        nonisolated(unsafe) var fractions: [Double] = []
        let uploaded = try await client.upload(
            file: file, metadata: VideoMetadata(title: "Lap 3", tags: ["track"], privacy: .unlisted),
            chunkSize: 1 << 20,
            progress: { fractions.append($0) })
        #expect(uploaded.id == "vid-42")
        #expect(uploaded.watchURL.absoluteString == "https://youtu.be/vid-42")
        #expect(MockGoogle.state.refreshes == 1)
        #expect(MockGoogle.state.received == payload, "every byte arrives in order")
        #expect(MockGoogle.state.statusQueries == 1, "the failed chunk is resumed from the server's byte count")
        // The chunk at 2 MiB failed half-way; the next one starts where the server said it got to.
        #expect(MockGoogle.state.chunkRanges.contains { $0.hasPrefix("bytes \(2 << 20)-") })
        #expect(MockGoogle.state.chunkRanges.contains { $0.hasPrefix("bytes \((2 << 20) + (1 << 20) / 2)-") })
        #expect(fractions.last == 1 && fractions.count >= 5)
        let snippet = MockGoogle.state.lastMetadata["snippet"] as? [String: Any]
        let status = MockGoogle.state.lastMetadata["status"] as? [String: Any]
        #expect(snippet?["title"] as? String == "Lap 3")
        #expect(status?["privacyStatus"] as? String == "unlisted")
    }

    @Test func rangeHeaderParsing() {
        #expect(YouTubeClient.nextOffset(from: "bytes=0-524287") == 524288)
        #expect(YouTubeClient.nextOffset(from: nil) == 0)
        #expect(YouTubeClient.formEncode(["b": "x y", "a": "1&2"]) == "a=1%262&b=x%20y")
    }

    @Test func fileStoreRoundTripsWithPrivatePermissions() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tok-\(UUID().uuidString)/token.json")
        let store = FileTokenStore(url: url)
        #expect(try store.load() == nil)
        let token = OAuthToken(
            accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(token)
        #expect(try store.load() == token)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try store.clear()
        #expect(try store.load() == nil)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
