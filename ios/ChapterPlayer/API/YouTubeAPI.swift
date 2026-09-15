import Foundation

enum YouTubeAPIError: Error {
    case badResponse(Int)
}

enum YouTubeAPI {
    private static let base = "https://www.googleapis.com/youtube/v3"

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        let token = try await AuthManager.shared.validAccessToken()
        var request = URLRequest(url: URL(string: base + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw YouTubeAPIError.badResponse(status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func fetchMyPlaylists() async throws -> [Playlist] {
        let result: PlaylistListResponse = try await get("/playlists?part=snippet,contentDetails&mine=true&maxResults=50")
        return result.items
    }

    static func fetchPlaylistItems(playlistId: String) async throws -> [PlaylistItem] {
        let result: PlaylistItemListResponse = try await get("/playlistItems?part=snippet&playlistId=\(playlistId)&maxResults=50")
        return result.items
    }

    static func fetchVideo(videoId: String) async throws -> Video? {
        let result: VideoListResponse = try await get("/videos?part=snippet,contentDetails&id=\(videoId)")
        return result.items.first
    }
}
