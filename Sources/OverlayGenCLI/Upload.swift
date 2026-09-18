import ArgumentParser
import Foundation
import YouTubeKit

struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload a video to YouTube (signs in with a device code on first use).")

    @Argument(help: "The video file to upload.")
    var path: String

    @Option(name: .long, help: "Video title.")
    var title: String

    @Option(name: .long, help: "Video description.")
    var description: String = ""

    @Option(name: .long, help: "Comma-separated tags.")
    var tags: String = ""

    @Option(name: .long, help: "private, unlisted or public.")
    var privacy: String = "private"

    @Option(name: .long, help: "Google OAuth client ID (or set OVERLAYGEN_YT_CLIENT_ID).")
    var clientID: String?

    @Option(name: .long, help: "Google OAuth client secret (or set OVERLAYGEN_YT_CLIENT_SECRET).")
    var clientSecret: String?

    @Flag(name: .long, help: "Forget the stored sign-in and exit.")
    var signOut = false

    func run() async throws {
        let store = FileTokenStore(url: FileTokenStore.defaultURL)
        if signOut {
            try store.clear()
            print("Signed out.")
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let credentials = YouTubeCredentials(
            clientID: clientID ?? environment["OVERLAYGEN_YT_CLIENT_ID"] ?? "",
            clientSecret: clientSecret ?? environment["OVERLAYGEN_YT_CLIENT_SECRET"] ?? "")
        guard credentials.isComplete else {
            throw ValidationError("Provide --client-id/--client-secret or the OVERLAYGEN_YT_CLIENT_* variables.")
        }
        guard let privacyValue = VideoMetadata.Privacy(rawValue: privacy) else {
            throw ValidationError("--privacy must be private, unlisted or public.")
        }
        let client = YouTubeClient(credentials: credentials, store: store)
        if !client.isSignedIn {
            let authorization = try await client.startDeviceAuthorization()
            print("Open \(authorization.verificationURL.absoluteString) and enter the code: \(authorization.userCode)")
            print("Waiting for approval…")
            _ = try await client.waitForAuthorization(authorization)
            print("Signed in; the token is stored in \(store.url.path).")
        }
        let metadata = VideoMetadata(
            title: title, description: description,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            privacy: privacyValue)
        let video = try await client.upload(
            file: URL(fileURLWithPath: path), metadata: metadata,
            progress: { fraction in FileHandle.standardError.write(Data("\rUploading… \(Int(fraction * 100))%".utf8)) })
        print("\nUploaded: \(video.watchURL.absoluteString)")
    }
}
