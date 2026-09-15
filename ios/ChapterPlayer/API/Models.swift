import Foundation

struct Thumbnail: Decodable {
    let url: String
}

struct Thumbnails: Decodable {
    let defaultThumbnail: Thumbnail?

    enum CodingKeys: String, CodingKey {
        case defaultThumbnail = "default"
    }
}

struct Snippet: Decodable {
    let title: String
    let description: String?
    let thumbnails: Thumbnails?
}

struct PlaylistContentDetails: Decodable {
    let itemCount: Int
}

struct Playlist: Decodable, Identifiable {
    let id: String
    let snippet: Snippet
    let contentDetails: PlaylistContentDetails
}

struct PlaylistListResponse: Decodable {
    let items: [Playlist]
}

struct ResourceId: Decodable {
    let videoId: String?
}

struct PlaylistItemSnippet: Decodable {
    let title: String
    let thumbnails: Thumbnails?
    let resourceId: ResourceId
}

struct PlaylistItem: Decodable, Identifiable {
    let id: String
    let snippet: PlaylistItemSnippet
}

struct PlaylistItemListResponse: Decodable {
    let items: [PlaylistItem]
}

struct VideoContentDetails: Decodable {
    let duration: String
}

struct Video: Decodable {
    let snippet: Snippet
    let contentDetails: VideoContentDetails
}

struct VideoListResponse: Decodable {
    let items: [Video]
}
