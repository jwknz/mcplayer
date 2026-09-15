import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "play.rectangle.on.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                        Text("MCPlayer")
                            .font(.headline)
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section("Legal") {
                    Link(destination: URL(string: "https://jkmcplayer.netlify.app/privacy.html")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://jkmcplayer.netlify.app/terms.html")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                Section("About") {
                    Text("MCPlayer plays your YouTube videos through YouTube's own player and reads chapter timestamps from each video's description, so you can jump between or loop a single chapter. It doesn't download, store, or redistribute any video content — everything streams directly from YouTube.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
        }
    }
}
