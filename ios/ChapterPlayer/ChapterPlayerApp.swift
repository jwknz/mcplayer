import SwiftUI

@main
struct ChapterPlayerApp: App {
    @StateObject private var nowPlaying = NowPlayingViewModel()
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                PlaylistsView(onSelectVideo: { videoId in
                    selectedTab = 1
                    Task { await nowPlaying.load(videoId: videoId) }
                })
                .tabItem {
                    Label("Playlists", systemImage: "music.note.list")
                }
                .tag(0)

                NowPlayingView(viewModel: nowPlaying)
                    .tabItem {
                        Label("Now playing", systemImage: "play.circle")
                    }
                    .tag(1)

                AboutView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(2)
            }
        }
    }
}
