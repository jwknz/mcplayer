import SwiftUI

struct PlaylistItemsView: View {
    let playlist: Playlist
    let onSelectVideo: (String) -> Void
    @State private var items: [PlaylistItem] = []
    @State private var statusMessage = "Loading\u{2026}"

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    if let videoId = item.snippet.resourceId.videoId {
                        Button {
                            onSelectVideo(videoId)
                        } label: {
                            HStack(spacing: 12) {
                                ThumbnailView(urlString: item.snippet.thumbnails?.defaultThumbnail?.url)
                                    .frame(width: 64, height: 48)
                                Text(item.snippet.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.snippet.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                items = try await YouTubeAPI.fetchPlaylistItems(playlistId: playlist.id)
                if items.isEmpty { statusMessage = "This playlist is empty." }
            } catch {
                statusMessage = "Couldn't load videos: \(error.localizedDescription)"
            }
        }
    }
}
