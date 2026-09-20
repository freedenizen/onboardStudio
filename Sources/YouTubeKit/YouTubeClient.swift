import Foundation

/// The OAuth client of the Google Cloud project the user created for Onboard Studio (type "TVs and
/// Limited Input devices"). Google treats the secret of installed apps as non-confidential.
public struct YouTubeCredentials: Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public var isComplete: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}

public struct OAuthToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public func isValid(at date: Date = Date()) -> Bool { expiresAt.timeIntervalSince(date) > 60 }
}

/// What the user must do to sign in: visit the URL and type the code.
public struct DeviceAuthorization: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let interval: Double
    public let expiresAt: Date
}

public struct VideoMetadata: Sendable, Equatable {
    public enum Privacy: String, Sendable, CaseIterable {
        case `private`
        case unlisted
        case `public`
    }

    public var title: String
    public var description: String
    public var tags: [String]
    public var privacy: Privacy
    /// YouTube category id; 17 = Sports, 2 = Autos & Vehicles.
    public var categoryID: String

    public init(
        title: String, description: String = "", tags: [String] = [], privacy: Privacy = .private,
        categoryID: String = "17"
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.privacy = privacy
        self.categoryID = categoryID
    }
}

public struct UploadedVideo: Sendable, Equatable {
    public let id: String
    public var watchURL: URL { URL(string: "https://youtu.be/\(id)") ?? URL(fileURLWithPath: "/") }
}

public enum YouTubeError: Error, CustomStringConvertible, Equatable {
    case missingCredentials
    case notSignedIn
    case accessDenied
    case codeExpired
    case badResponse(Int, String)
    case uploadFailed(String)

    public var description: String {
        switch self {
        case .missingCredentials: "Enter the Google OAuth client ID and secret in Settings first."
        case .notSignedIn: "Sign in to YouTube first."
        case .accessDenied: "Google reported that access was denied."
        case .codeExpired: "The sign-in code expired before it was entered."
        case .badResponse(let status, let body): "Unexpected response \(status): \(body)"
        case .uploadFailed(let why): "Upload failed: \(why)"
        }
    }
}

/// The Google endpoints, overridable so tests can point the client at a mock.
public struct YouTubeEndpoints: Sendable {
    public var deviceCode: URL
    public var token: URL
    public var upload: URL

    public init(deviceCode: URL, token: URL, upload: URL) {
        self.deviceCode = deviceCode
        self.token = token
        self.upload = upload
    }

    public static let google = YouTubeEndpoints(
        deviceCode: URL(string: "https://oauth2.googleapis.com/device/code")!,
        token: URL(string: "https://oauth2.googleapis.com/token")!,
        upload: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos")!)
}

/// Signs in with the OAuth device flow and uploads videos with the resumable protocol.
public final class YouTubeClient: Sendable {
    public static let scope = "https://www.googleapis.com/auth/youtube.upload"
    public let credentials: YouTubeCredentials
    public let store: any TokenStore
    let session: URLSession
    let endpoints: YouTubeEndpoints
    /// Seconds to wait before polling again / retrying; tests shorten it.
    let sleeper: @Sendable (Double) async throws -> Void

    public init(
        credentials: YouTubeCredentials, store: any TokenStore, session: URLSession = .shared,
        endpoints: YouTubeEndpoints = .google,
        sleeper: @escaping @Sendable (Double) async throws -> Void = { seconds in
            try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        }
    ) {
        self.credentials = credentials
        self.store = store
        self.session = session
        self.endpoints = endpoints
        self.sleeper = sleeper
    }

    // MARK: - Sign-in

    public var isSignedIn: Bool { (try? store.load()) != nil }

    public func signOut() throws { try store.clear() }

    /// Step 1: ask Google for a code the user enters at the verification URL.
    public func startDeviceAuthorization() async throws -> DeviceAuthorization {
        guard credentials.isComplete else { throw YouTubeError.missingCredentials }
        let json = try await postForm(
            endpoints.deviceCode, ["client_id": credentials.clientID, "scope": Self.scope])
        guard let device = json["device_code"] as? String, let user = json["user_code"] as? String,
            let urlText = (json["verification_url"] as? String) ?? (json["verification_uri"] as? String),
            let url = URL(string: urlText)
        else { throw YouTubeError.badResponse(200, "\(json)") }
        let interval = (json["interval"] as? Double) ?? 5
        let expiresIn = (json["expires_in"] as? Double) ?? 1800
        return DeviceAuthorization(
            deviceCode: device, userCode: user, verificationURL: url, interval: interval,
            expiresAt: Date().addingTimeInterval(expiresIn))
    }

    /// Step 2: poll until the user has approved (or the code expires). Stores the token.
    public func waitForAuthorization(_ authorization: DeviceAuthorization) async throws -> OAuthToken {
        var interval = authorization.interval
        while Date() < authorization.expiresAt {
            try Task.checkCancellation()
            let (status, json) = try await postFormWithStatus(
                endpoints.token,
                [
                    "client_id": credentials.clientID, "client_secret": credentials.clientSecret,
                    "device_code": authorization.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
            if status == 200, let token = Self.token(from: json) {
                try store.save(token)
                return token
            }
            switch json["error"] as? String {
            case "authorization_pending": break
            case "slow_down": interval += 5
            case "access_denied": throw YouTubeError.accessDenied
            case "expired_token": throw YouTubeError.codeExpired
            default: throw YouTubeError.badResponse(status, "\(json)")
            }
            try await sleeper(interval)
        }
        throw YouTubeError.codeExpired
    }

    /// A token that is valid now, refreshing the stored one when it has expired.
    public func validToken() async throws -> OAuthToken {
        guard let stored = try store.load() else { throw YouTubeError.notSignedIn }
        if stored.isValid() { return stored }
        guard let refresh = stored.refreshToken else { throw YouTubeError.notSignedIn }
        let (status, json) = try await postFormWithStatus(
            endpoints.token,
            [
                "client_id": credentials.clientID, "client_secret": credentials.clientSecret,
                "refresh_token": refresh, "grant_type": "refresh_token",
            ])
        guard status == 200, var token = Self.token(from: json) else {
            throw YouTubeError.badResponse(status, "\(json)")
        }
        if token.refreshToken == nil { token.refreshToken = refresh }
        try store.save(token)
        return token
    }

    static func token(from json: [String: Any]) -> OAuthToken? {
        guard let access = json["access_token"] as? String else { return nil }
        let expires = (json["expires_in"] as? Double) ?? 3600
        return OAuthToken(
            accessToken: access, refreshToken: json["refresh_token"] as? String,
            expiresAt: Date().addingTimeInterval(expires))
    }

    // MARK: - Upload

    /// Uploads `file` in `chunkSize` pieces with the resumable protocol, retrying interrupted
    /// chunks from where the server says it stopped. `progress` is 0…1.
    public func upload(
        file: URL, metadata: VideoMetadata, chunkSize: Int = 8 << 20, maxRetries: Int = 5,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> UploadedVideo {
        let token = try await validToken()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let total = Int(try handle.seekToEnd())
        guard total > 0 else { throw YouTubeError.uploadFailed("the file is empty") }
        let location = try await startUploadSession(token: token, metadata: metadata, totalBytes: total)

        var offset = 0
        var retries = 0
        while offset < total {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, total)
            try handle.seek(toOffset: UInt64(offset))
            let chunk = try handle.read(upToCount: end - offset) ?? Data()
            var request = URLRequest(url: location)
            request.httpMethod = "PUT"
            request.setValue("bytes \(offset)-\(end - 1)/\(total)", forHTTPHeaderField: "Content-Range")
            request.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")
            request.setValue("video/*", forHTTPHeaderField: "Content-Type")
            let outcome = await sendChunk(request, chunk)
            switch outcome.status {
            case 200, 201:
                progress(1)
                guard let json = try? JSONSerialization.jsonObject(with: outcome.body) as? [String: Any],
                    let id = json["id"] as? String
                else { throw YouTubeError.badResponse(outcome.status, Self.text(outcome.body)) }
                return UploadedVideo(id: id)
            case 308:
                offset = Self.nextOffset(from: outcome.range) ?? end
                retries = 0
                progress(Double(offset) / Double(total))
            case 404:
                throw YouTubeError.uploadFailed("the upload session expired")
            default:
                // Network error or 5xx: ask the server where it got to and go on from there.
                retries += 1
                guard retries <= maxRetries else {
                    throw YouTubeError.uploadFailed("gave up after \(maxRetries) retries (status \(outcome.status))")
                }
                try await sleeper(min(pow(2, Double(retries - 1)), 30))
                if let resumed = try await queryUploadStatus(location: location, totalBytes: total) {
                    if let id = resumed.completedID { return UploadedVideo(id: id) }
                    offset = resumed.nextOffset
                }
            }
        }
        throw YouTubeError.uploadFailed("the server never confirmed the upload")
    }

    struct ChunkOutcome {
        let status: Int
        let body: Data
        let range: String?
    }

    /// Sends one chunk; a transport error reads as status 0.
    func sendChunk(_ request: URLRequest, _ chunk: Data) async -> ChunkOutcome {
        do {
            let (data, response) = try await session.upload(for: request, from: chunk)
            let http = response as? HTTPURLResponse
            return ChunkOutcome(
                status: http?.statusCode ?? 0, body: data, range: http?.value(forHTTPHeaderField: "Range"))
        } catch {
            return ChunkOutcome(status: 0, body: Data(), range: nil)
        }
    }

    static func text(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

    func startUploadSession(token: OAuthToken, metadata: VideoMetadata, totalBytes: Int) async throws -> URL {
        var components = URLComponents(url: endpoints.upload, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"), URLQueryItem(name: "part", value: "snippet,status"),
        ]
        guard let url = components?.url else { throw YouTubeError.uploadFailed("bad upload URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(totalBytes)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        let body: [String: Any] = [
            "snippet": [
                "title": metadata.title, "description": metadata.description, "tags": metadata.tags,
                "categoryId": metadata.categoryID,
            ],
            "status": ["privacyStatus": metadata.privacy.rawValue, "selfDeclaredMadeForKids": false],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YouTubeError.badResponse(0, "no response") }
        guard http.statusCode == 200, let location = http.value(forHTTPHeaderField: "Location"),
            let url = URL(string: location)
        else { throw YouTubeError.badResponse(http.statusCode, Self.text(data)) }
        return url
    }

    struct ResumeStatus {
        let nextOffset: Int
        let completedID: String?
    }

    func queryUploadStatus(location: URL, totalBytes: Int) async throws -> ResumeStatus? {
        var request = URLRequest(url: location)
        request.httpMethod = "PUT"
        request.setValue("bytes */\(totalBytes)", forHTTPHeaderField: "Content-Range")
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse
        else { return nil }
        switch http.statusCode {
        case 308:
            return ResumeStatus(
                nextOffset: Self.nextOffset(from: http.value(forHTTPHeaderField: "Range")) ?? 0, completedID: nil)
        case 200, 201:
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return ResumeStatus(nextOffset: totalBytes, completedID: json?["id"] as? String)
        case 404: throw YouTubeError.uploadFailed("the upload session expired")
        default: return nil
        }
    }

    /// `Range: bytes=0-524287` → 524288; no header means nothing was received.
    static func nextOffset(from range: String?) -> Int? {
        guard let range else { return 0 }
        guard let dash = range.lastIndex(of: "-"), let last = Int(range[range.index(after: dash)...]) else { return 0 }
        return last + 1
    }

    // MARK: - HTTP helpers

    func postForm(_ url: URL, _ fields: [String: String]) async throws -> [String: Any] {
        let (status, json) = try await postFormWithStatus(url, fields)
        guard status == 200 else { throw YouTubeError.badResponse(status, "\(json)") }
        return json
    }

    func postFormWithStatus(_ url: URL, _ fields: [String: String]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (status, json)
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.keys.sorted().map { key in
            let value = fields[key]?.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(value)"
        }
        .joined(separator: "&")
    }
}
