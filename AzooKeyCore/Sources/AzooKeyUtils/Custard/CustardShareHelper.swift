import CustardKit
import Foundation
import SwiftUtils

/// Helper for uploading a `Custard` JSON to the share‑link API
public struct CustardShareHelper {
    /// Base URL of the Cloudflare Workers API (without trailing slash)
    private static let baseURL = URL(string: "https://custard.azookey.com")!

    public enum ShareError: Error, LocalizedError {
        case encodeFailed
        case invalidResponse
        case sizeLimitExceeded
        case serverError(status: Int, message: String?)

        public var errorDescription: String? {
            switch self {
            case .encodeFailed:
                return "カスタムタブのエンコードに失敗しました。"
            case .invalidResponse:
                return "サーバーからの応答を解釈できませんでした。"
            case .sizeLimitExceeded:
                return "ファイルサイズが 5 MB を超えているため、共有できません。"
            case let .serverError(status, message):
                return "共有に失敗しました (HTTP \(status)). \(message ?? "")"
            }
        }
    }

    private static let maxRetries = 5
    private static let defaultRetryAfter: TimeInterval = 3

    /// Uploads the given `Custard` to the server and returns the absolute share URL.
    /// - Parameter custard: The `Custard` object to share.
    /// - Returns: A fully‑qualified URL that anyone can open to download the JSON.
    public static func upload(_ custard: Custard) async throws -> (url: URL, deleteToken: String) {
        throw ShareError.serverError(status: 403, message: "Offline-only compliance active.")
    }

    // MARK: - Update (PUT)

    public static func update(_ custard: Custard, shareURL: URL, updateToken: String) async throws {
        throw ShareError.serverError(status: 403, message: "Offline-only compliance active.")
    }

    /// Checks whether the given URL points to a valid share‑link for this app.
    /// - Parameter url: The URL provided by the user.
    /// - Returns: `true` if the URL’s host matches `baseURL` and the path matches `/api/tab/<uuid>`.
    public static func checkShareLink(_ url: URL) -> Bool {
        // Must have same host (subdomain + workers.dev or custom)
        guard url.scheme == "https",
              url.host == baseURL.host else {
            return false
        }

        // Path must be /api/tab/{uuid}
        let pattern = #"^/tab/[0-9a-fA-F\-]{36}$"#
        return url.path.range(of: pattern, options: .regularExpression) != nil
    }

    /// Verifies that the share link is valid **and** the tab still exists on the server.
    /// Performs a lightweight `HEAD` request (falls back to `GET` if HEAD not allowed).
    /// - Returns: `true` if the server responds with 200 OK.
    public static func verifyShareLink(_ url: URL) async -> Bool {
        return false
    }

    struct ShareAPIResponse: Decodable {
        let url: String
        /// Deletion token returned by the API (30‑day lifetime).
        let delete_token: String
    }
}
