import SwiftUI

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var videoTitle = ""
    @Published var statusMessage = "Paste a YouTube video URL or ID, or pick one from Playlists."
    @Published var chapters: [Chapter] = []
    @Published var activeChapterIndex: Int = -1
    @Published var repeatTrack = false
    @Published var loopChapter = false

    let bridge = PlayerBridge()

    func loadFromInput() {
        guard let videoId = Self.parseVideoId(urlText) else {
            statusMessage = "Couldn't recognize that as a YouTube video URL or ID."
            return
        }
        Task { await load(videoId: videoId) }
    }

    func load(videoId: String) async {
        chapters = []
        activeChapterIndex = -1
        videoTitle = "Loading\u{2026}"
        statusMessage = ""
        bridge.load(videoId: videoId)

        do {
            guard let video = try await YouTubeAPI.fetchVideo(videoId: videoId) else {
                videoTitle = ""
                statusMessage = "Video not found (private, deleted, or wrong ID)."
                return
            }
            videoTitle = video.snippet.title
            let duration = ChapterParser.parseDuration(video.contentDetails.duration)
            chapters = ChapterParser.parseChapters(description: video.snippet.description ?? "", duration: duration)
            statusMessage = chapters.isEmpty
                ? "No chapter timestamps found in the description."
                : "\(chapters.count) chapters found"
        } catch {
            videoTitle = ""
            statusMessage = "Couldn't load video: \(error.localizedDescription)"
        }
    }

    /// Called on every player time update. Mirrors the loop-boundary fix
    /// verified in the web app's app.js: pin to the last-known active
    /// chapter rather than re-deriving the index from raw time first, since
    /// the ~400ms poll interval can land after the chapter boundary has
    /// already passed, which would otherwise silently start "looping" the
    /// next chapter instead of seeking back.
    func onTimeUpdate(_ time: Double) {
        if loopChapter, activeChapterIndex >= 0, activeChapterIndex < chapters.count {
            let looping = chapters[activeChapterIndex]
            if time >= looping.end {
                bridge.seek(to: looping.start)
                return
            }
        }
        activeChapterIndex = currentChapterIndex(for: time)
    }

    func onPlaybackEnded() {
        if repeatTrack {
            bridge.seek(to: 0)
            bridge.play()
        }
    }

    private func currentChapterIndex(for t: Double) -> Int {
        for (i, ch) in chapters.enumerated() where t >= ch.start && t < ch.end {
            return i
        }
        if let last = chapters.indices.last, t >= chapters[last].end {
            return last
        }
        return -1
    }

    func selectChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        bridge.seek(to: chapters[index].start)
        bridge.play()
    }

    func previousChapter() {
        let idx = currentChapterIndex(for: bridge.currentTime)
        let target = idx > 0 ? chapters[idx - 1].start : 0
        bridge.seek(to: target)
    }

    func nextChapter() {
        let idx = currentChapterIndex(for: bridge.currentTime)
        if idx >= 0, idx < chapters.count - 1 {
            bridge.seek(to: chapters[idx + 1].start)
        }
    }

    static func parseVideoId(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[a-zA-Z0-9_-]{11}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        guard let components = URLComponents(string: trimmed) else { return nil }
        if let host = components.host, host.contains("youtu.be") {
            let parts = components.path.split(separator: "/")
            return parts.first.map(String.init)
        }
        if components.path.hasPrefix("/shorts/") || components.path.hasPrefix("/embed/") {
            let parts = components.path.split(separator: "/")
            return parts.count > 1 ? String(parts[1]) : nil
        }
        return components.queryItems?.first(where: { $0.name == "v" })?.value
    }
}

struct NowPlayingView: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @FocusState private var urlFieldFocused: Bool
    @State private var isPlayerHidden = false
    @State private var isFullScreen = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    TextField("Paste a YouTube video URL or ID", text: $viewModel.urlText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($urlFieldFocused)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                    if !viewModel.urlText.isEmpty {
                        Button {
                            Task { @MainActor in submit() }
                        } label: {
                            Text("Load")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 14)

                Group {
                    if isPlayerHidden {
                        // A 1pt-tall view, not zero and not `.hidden()` —
                        // the video keeps playing because the element is
                        // still laid out and visible. Actually hiding it
                        // (display:none, zero-size, or removing it from
                        // the hierarchy) makes YouTube's player treat the
                        // tab as backgrounded and pause it.
                        PlayerView(bridge: viewModel.bridge)
                            .frame(height: 1)
                    } else {
                        PlayerView(bridge: viewModel.bridge)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    }
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: isPlayerHidden ? 2 : 14, style: .continuous))
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.2), value: isPlayerHidden)

                HStack(spacing: 16) {
                    Spacer()
                    Button {
                        isPlayerHidden.toggle()
                    } label: {
                        Label(isPlayerHidden ? "Show video" : "Hide video", systemImage: isPlayerHidden ? "eye" : "eye.slash")
                            .font(.caption)
                    }
                    if !isPlayerHidden {
                        Button {
                            isFullScreen = true
                        } label: {
                            Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 2) {
                    if !viewModel.videoTitle.isEmpty {
                        Text(viewModel.videoTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)

                TransportBar(viewModel: viewModel)
                    .padding(.top, 8)

                Divider().padding(.top, 14)

                if viewModel.chapters.isEmpty {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Chapters will show up here once you load a video that has them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 24)
                    Spacer()
                } else {
                    List {
                        ForEach(Array(viewModel.chapters.enumerated()), id: \.element.id) { index, chapter in
                            ChapterRow(
                                index: index,
                                chapter: chapter,
                                isActive: index == viewModel.activeChapterIndex
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.selectChapter(index) }
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Now playing")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(viewModel.bridge.$currentTime) { time in
                viewModel.onTimeUpdate(time)
            }
            .fullScreenCover(isPresented: $isFullScreen) {
                FullScreenPlayerView(viewModel: viewModel, isPresented: $isFullScreen)
            }
        }
    }

    private func submit() {
        urlFieldFocused = false
        viewModel.loadFromInput()
    }
}

private struct TransportBar: View {
    @ObservedObject var viewModel: NowPlayingViewModel

    var body: some View {
        HStack(spacing: 22) {
            ToggleGlyph(systemName: "repeat", isOn: viewModel.repeatTrack) {
                viewModel.repeatTrack.toggle()
            }

            Button { viewModel.previousChapter() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }
            .foregroundStyle(Color.primary)

            Button {
                if viewModel.bridge.isPlaying {
                    viewModel.bridge.pause()
                } else {
                    viewModel.bridge.play()
                }
            } label: {
                Image(systemName: viewModel.bridge.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: Circle())
            }

            Button { viewModel.nextChapter() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
            }
            .foregroundStyle(Color.primary)

            ToggleGlyph(systemName: "repeat.1", isOn: viewModel.loopChapter) {
                viewModel.loopChapter.toggle()
            }
        }
    }
}

private struct ToggleGlyph: View {
    let systemName: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(isOn ? Color.accentColor.opacity(0.15) : .clear, in: Circle())
        }
    }
}

private struct ChapterRow: View {
    let index: Int
    let chapter: Chapter
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color(.secondarySystemBackground))
                    .frame(width: 28, height: 28)
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    .lineLimit(2)
                Text("\(ChapterParser.formatTime(chapter.start)) \u{2013} \(ChapterParser.formatTime(chapter.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            isActive ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct FullScreenPlayerView: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .white.opacity(0.25))
                }
            }
            .padding()

            // Same shared PlayerBridge/webView as the inline player, just
            // reparented into this container — playback position carries
            // straight over, nothing reloads.
            PlayerView(bridge: viewModel.bridge)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)

            TransportBar(viewModel: viewModel)
                .padding(.top, 24)
                .tint(.white)
                .foregroundStyle(.white)

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
