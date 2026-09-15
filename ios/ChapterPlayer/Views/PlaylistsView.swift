import SwiftUI

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var statusMessage = "Loading playlists\u{2026}"

    func load(isSignedIn: Bool) async {
        guard isSignedIn else {
            statusMessage = "Sign in to load your playlists."
            playlists = []
            return
        }
        statusMessage = "Loading playlists\u{2026}"
        do {
            playlists = try await YouTubeAPI.fetchMyPlaylists()
            statusMessage = playlists.isEmpty ? "No playlists found on this account." : ""
        } catch {
            statusMessage = "Couldn't load playlists: \(error.localizedDescription)"
        }
    }
}

struct PlaylistsView: View {
    let onSelectVideo: (String) -> Void
    @StateObject private var viewModel = PlaylistsViewModel()
    @StateObject private var auth = AuthManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    if viewModel.playlists.isEmpty {
                        emptyState
                    } else {
                        List(viewModel.playlists) { playlist in
                            NavigationLink {
                                PlaylistItemsView(playlist: playlist, onSelectVideo: onSelectVideo)
                            } label: {
                                PlaylistRow(playlist: playlist)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await viewModel.load(isSignedIn: auth.isSignedIn) }
                    }
                } else {
                    signInState
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Sign out", role: .destructive) { auth.signOut() }
                    }
                }
            }
            .task(id: auth.isSignedIn) {
                await viewModel.load(isSignedIn: auth.isSignedIn)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(viewModel.statusMessage.isEmpty ? "No playlists yet" : viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signInState: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 4) {
                Text("Your playlists live here")
                    .font(.headline)
                Text("Sign in with Google to browse them and jump straight to a video.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button {
                auth.signIn()
            } label: {
                Label("Sign in with Google", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 48)

            if let error = auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(urlString: playlist.snippet.thumbnails?.defaultThumbnail?.url)
                .frame(width: 64, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.snippet.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text("\(playlist.contentDetails.itemCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ThumbnailView: View {
    let urlString: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
