import Foundation

struct GitHubReleaseInfo: Equatable, Sendable {
    var version: String
    var tagName: String
    var releasePageURL: URL
    var downloadURL: URL
    var assetFileName: String
}

enum AppVersion {
    static func current(bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func normalizedTag(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }
}

enum GitHubReleaseError: LocalizedError {
    case badResponse
    case noReleaseAssets
    case noMatchingAsset(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            "GitHub вернул неожиданный ответ."
        case .noReleaseAssets:
            "В релизе нет файлов для скачивания."
        case let .noMatchingAsset(name):
            "Не найден установщик \(name)."
        }
    }
}

struct GitHubReleaseFetcher: Sendable {
    var repository: String
    var session: URLSession
    var architecture: String

    static let production = GitHubReleaseFetcher(
        repository: "ZeppelinOFF/vidgetYo",
        session: .shared,
        architecture: Self.hostArchitecture
    )

    static var hostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    func latestNewerThan(current: String) async throws -> GitHubReleaseInfo? {
        let release = try await fetchLatestRelease()
        guard AppVersion.isVersion(release.version, newerThan: current) else {
            return nil
        }
        return release
    }

    func fetchLatestRelease() async throws -> GitHubReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("VidgetYo", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GitHubReleaseError.badResponse
        }
        return try Self.parseRelease(data: data, architecture: architecture)
    }

    func downloadAsset(
        info: GitHubReleaseInfo,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let (tempURL, response) = try await session.download(from: info.downloadURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GitHubReleaseError.badResponse
        }
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let destination = downloads.appendingPathComponent(info.assetFileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        return destination
    }

    static func parseRelease(data: Data, architecture: String) throws -> GitHubReleaseInfo {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw GitHubReleaseError.badResponse
        }
        let tag = text(object["tag_name"]) ?? ""
        let version = AppVersion.normalizedTag(tag)
        guard !version.isEmpty else { throw GitHubReleaseError.badResponse }
        guard let releasePage = url(object["html_url"]) else { throw GitHubReleaseError.badResponse }
        let assets = assetRows(in: object)
        guard !assets.isEmpty else { throw GitHubReleaseError.noReleaseAssets }
        let preferredName = dmgAssetName(version: version, architecture: architecture)
        let asset = assets.first(where: { $0.name == preferredName })
            ?? assets.first(where: { $0.name.hasPrefix("VidgetYo-") && $0.name.hasSuffix("-\(architecture).dmg") })
        guard let asset, let downloadURL = asset.downloadURL else {
            throw GitHubReleaseError.noMatchingAsset(preferredName)
        }
        return GitHubReleaseInfo(
            version: version,
            tagName: tag,
            releasePageURL: releasePage,
            downloadURL: downloadURL,
            assetFileName: asset.name
        )
    }

    static func dmgAssetName(version: String, architecture: String) -> String {
        "VidgetYo-\(version)-macOS27-\(architecture).dmg"
    }

    private struct AssetRow {
        var name: String
        var downloadURL: URL?
    }

    private static func assetRows(in release: [String: Any]) -> [AssetRow] {
        guard let raw = release["assets"] as? [Any] else { return [] }
        return raw.compactMap { item in
            guard let row = item as? [String: Any], let name = text(row["name"]) else { return nil }
            return AssetRow(name: name, downloadURL: url(row["browser_download_url"]))
        }
    }

    private static func text(_ value: Any?) -> String? {
        value as? String
    }

    private static func url(_ value: Any?) -> URL? {
        guard let raw = value as? String else { return nil }
        return URL(string: raw)
    }
}
