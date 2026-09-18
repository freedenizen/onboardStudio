import Foundation
import SwiftUI
import YouTubeKit

/// The signed-in YouTube account and the upload in progress. Client credentials live in
/// UserDefaults (Google treats an installed app's secret as public); the token in the keychain.
@Observable
final class YouTubeModel {
    enum Phase: Equatable {
        case idle
        case awaitingCode(userCode: String, url: URL)
        case uploading(Double)
        case done(URL)
        case failed(String)
    }

    var phase: Phase = .idle
    private(set) var isSignedIn = false
    private var task: Task<Void, Never>?
    private let store = KeychainTokenStore()

    init() { isSignedIn = (try? store.load()) != nil }

    static var credentials: YouTubeCredentials {
        YouTubeCredentials(
            clientID: UserDefaults.standard.string(forKey: "youtubeClientID") ?? "",
            clientSecret: UserDefaults.standard.string(forKey: "youtubeClientSecret") ?? "")
    }

    var hasCredentials: Bool { Self.credentials.isComplete }

    private func client() -> YouTubeClient { YouTubeClient(credentials: Self.credentials, store: store) }

    /// Runs the device flow: shows the code, waits for approval.
    func signIn() {
        guard task == nil else { return }
        let client = client()
        task = Task {
            defer { task = nil }
            do {
                let authorization = try await client.startDeviceAuthorization()
                phase = .awaitingCode(userCode: authorization.userCode, url: authorization.verificationURL)
                _ = try await client.waitForAuthorization(authorization)
                isSignedIn = true
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed("\(error)")
            }
        }
    }

    func signOut() {
        try? store.clear()
        isSignedIn = false
        phase = .idle
    }

    func upload(file: URL, metadata: VideoMetadata) {
        guard task == nil else { return }
        let client = client()
        phase = .uploading(0)
        task = Task {
            defer { task = nil }
            do {
                let video = try await Task.detached(priority: .userInitiated) {
                    try await client.upload(
                        file: file, metadata: metadata,
                        progress: { fraction in Task { @MainActor in self.phase = .uploading(fraction) } })
                }.value
                phase = .done(video.watchURL)
            } catch is CancellationError {
                phase = .failed("Upload cancelled.")
            } catch {
                phase = .failed("\(error)")
            }
        }
    }

    func cancel() { task?.cancel() }
    var isBusy: Bool { task != nil }
}
