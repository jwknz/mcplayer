import Foundation

enum Config {
    static let clientID = "502694808659-sg5aqc59n8l79jc490lmtk1c3t5mi4v2.apps.googleusercontent.com"

    static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    static var redirectURI: String { redirectScheme + ":/oauth2redirect" }
}
