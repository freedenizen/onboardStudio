import Foundation
import Security

/// Where the OAuth token lives between runs.
public protocol TokenStore: Sendable {
    func load() throws -> OAuthToken?
    func save(_ token: OAuthToken) throws
    func clear() throws
}

/// For tests and one-off runs.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: OAuthToken?

    public init(token: OAuthToken? = nil) { self.token = token }

    public func load() throws -> OAuthToken? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func save(_ token: OAuthToken) throws {
        lock.lock()
        self.token = token
        lock.unlock()
    }

    public func clear() throws {
        lock.lock()
        token = nil
        lock.unlock()
    }
}

/// A JSON file with owner-only permissions (the CLI uses this).
public struct FileTokenStore: TokenStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appending(path: "OnboardStudio/youtube-token.json")
    }

    public func load() throws -> OAuthToken? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func save(_ token: OAuthToken) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(token).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// The login keychain (the app uses this).
public struct KeychainTokenStore: TokenStore {
    /// The service the app used before it was renamed from OverlayGen. Read once, to carry an
    /// existing sign-in across the rename; never written.
    public static let legacyService = "com.overlaygen.youtube"

    public let service: String
    public let account: String

    public init(service: String = "com.onboardstudio.youtube", account: String = "oauth") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> OAuthToken? {
        if let token = try Self.read(service: service, account: account) { return token }
        // Fall back to the pre-rename service so an existing sign-in survives the rename. The
        // next `save` writes it under the current service.
        guard service != Self.legacyService else { return nil }
        return try Self.read(service: Self.legacyService, account: account)
    }

    private static func read(service: String, account: String) throws -> OAuthToken? {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func save(_ token: OAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.status(added) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    public enum KeychainError: Error, CustomStringConvertible {
        case status(OSStatus)
        public var description: String {
            if case .status(let code) = self {
                return "Keychain error \(code): \(SecCopyErrorMessageString(code, nil) as String? ?? "")"
            }
            return "Keychain error"
        }
    }
}
