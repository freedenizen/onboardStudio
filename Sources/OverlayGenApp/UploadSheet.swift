import AppKit
import SwiftUI
import YouTubeKit

/// Signs in to YouTube (device code) and uploads a finished export.
struct UploadSheet: View {
    @Environment(YouTubeModel.self) private var youtube
    @Environment(\.dismiss) private var dismiss
    let file: URL
    @State private var title = ""
    @State private var descriptionText = ""
    @State private var tags = ""
    @State private var privacy = VideoMetadata.Privacy.private
    @AppStorage("youtubeClientID") private var clientID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upload to YouTube").font(.title2)
            Text(file.lastPathComponent).foregroundStyle(.secondary)
            if !youtube.hasCredentials {
                Text(
                    "Enter the Google OAuth client ID and secret in Settings ▸ YouTube first "
                        + "(see docs/youtube.md for how to create them)."
                )
                .foregroundStyle(.orange)
            }
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $descriptionText, axis: .vertical).lineLimit(3...6)
                TextField("Tags (comma separated)", text: $tags)
                Picker("Privacy", selection: $privacy) {
                    Text("Private").tag(VideoMetadata.Privacy.private)
                    Text("Unlisted").tag(VideoMetadata.Privacy.unlisted)
                    Text("Public").tag(VideoMetadata.Privacy.public)
                }
            }
            .formStyle(.grouped)
            .frame(height: 230)
            status
            HStack {
                if youtube.isSignedIn {
                    Button("Sign Out") { youtube.signOut() }.disabled(youtube.isBusy)
                }
                Spacer()
                if youtube.isBusy {
                    Button("Cancel") { youtube.cancel() }
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    if youtube.isSignedIn {
                        Button("Upload") { start() }.keyboardShortcut(.defaultAction)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Sign In with Google…") { youtube.signIn() }.keyboardShortcut(.defaultAction)
                            .disabled(!youtube.hasCredentials)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if title.isEmpty { title = file.deletingPathExtension().lastPathComponent }
            youtube.phase = .idle
        }
    }

    @ViewBuilder var status: some View {
        switch youtube.phase {
        case .idle:
            Text(youtube.isSignedIn ? "Signed in to YouTube." : "Not signed in.").font(.callout)
                .foregroundStyle(.secondary)
        case .awaitingCode(let code, let url):
            VStack(alignment: .leading, spacing: 8) {
                Text("Go to \(url.absoluteString) and enter this code:").font(.callout)
                HStack {
                    Text(code).font(.system(.title, design: .monospaced)).textSelection(.enabled)
                    Button("Copy Code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                    Button("Open Google") { NSWorkspace.shared.open(url) }
                }
                Text("Waiting for approval…").font(.caption).foregroundStyle(.secondary)
            }
        case .uploading(let fraction):
            ProgressView(value: fraction) { Text("Uploading… \(Int(fraction * 100))%") }
        case .done(let watchURL):
            HStack {
                Text("Uploaded: \(watchURL.absoluteString)").textSelection(.enabled)
                Button("Open") { NSWorkspace.shared.open(watchURL) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(watchURL.absoluteString, forType: .string)
                }
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    func start() {
        let metadata = VideoMetadata(
            title: title.trimmingCharacters(in: .whitespaces), description: descriptionText,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            privacy: privacy)
        youtube.upload(file: file, metadata: metadata)
    }
}
