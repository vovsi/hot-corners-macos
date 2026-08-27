import AppKit

/// Checks GitHub Releases for a newer build of the app and installs it in place.
///
/// There are no hand-maintained version numbers: `build.sh` stamps the app with
/// `CFBundleVersion` = `git rev-list --count HEAD` (a number that only ever grows)
/// and publishes a release tagged `build-<count>`. Comparing those two numbers is
/// the whole update check.
enum Updater {
    static let repoOwner = "vovsi"
    static let repoName = "hot-corners-macos"

    struct Release {
        let build: Int
        let title: String
        let notes: String
        let assetURL: URL
        let pageURL: URL
    }

    enum CheckResult {
        case upToDate(build: Int)
        case available(Release)
        case noReleases
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case unknownLocalBuild
        case untrustedAsset
        case unpackFailed(String)
        case appNotFoundInArchive

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub returned an unexpected response."
            case .unknownLocalBuild: return "This build has no version stamp — rebuild it with build.sh."
            case .untrustedAsset: return "The release asset is not hosted on the expected repository."
            case .unpackFailed(let message): return "Could not unpack the update: \(message)"
            case .appNotFoundInArchive: return "The downloaded archive did not contain Hot Corners.app."
            }
        }
    }

    /// Build number baked into the running bundle, or `nil` for un-stamped builds.
    static var localBuild: Int? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        return Int(raw)
    }

    static var localCommit: String? {
        Bundle.main.infoDictionary?["GitCommit"] as? String
    }

    // MARK: - Check

    static func check(completion: @escaping (Result<CheckResult, Error>) -> Void) {
        guard let local = localBuild else {
            DispatchQueue.main.async { completion(.failure(UpdateError.unknownLocalBuild)) }
            return
        }

        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<CheckResult, Error>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }

            if let error { return finish(.failure(error)) }
            guard let http = response as? HTTPURLResponse else { return finish(.failure(UpdateError.badResponse)) }
            if http.statusCode == 404 { return finish(.success(.noReleases)) }
            guard http.statusCode == 200, let data else { return finish(.failure(UpdateError.badResponse)) }

            guard let release = parseRelease(data) else { return finish(.failure(UpdateError.badResponse)) }
            finish(.success(release.build > local ? .available(release) : .upToDate(build: local)))
        }.resume()
    }

    private static func parseRelease(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let build = Int(tag.replacingOccurrences(of: "build-", with: "")),
              let pageURLString = json["html_url"] as? String,
              let pageURL = URL(string: pageURLString),
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }

        let zip = assets.first {
            ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true
        }
        guard let urlString = zip?["browser_download_url"] as? String,
              let assetURL = URL(string: urlString),
              isTrusted(assetURL)
        else { return nil }

        let title = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag
        let notes = (json["body"] as? String) ?? ""
        return Release(build: build, title: title, notes: notes, assetURL: assetURL, pageURL: pageURL)
    }

    /// Only ever download from this repository's own release storage.
    private static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        let path = url.path
        return (host == "github.com" && path.hasPrefix("/\(repoOwner)/\(repoName)/"))
            || host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
    }

    // MARK: - Install

    /// Downloads the release, unpacks it, and hands the swap-and-relaunch off to a
    /// detached shell script (the running bundle can't replace itself in place).
    static func install(_ release: Release, completion: @escaping (Error?) -> Void) {
        URLSession.shared.downloadTask(with: release.assetURL) { tempURL, response, error in
            let fail: (Error) -> Void = { error in
                DispatchQueue.main.async { completion(error) }
            }

            if let error { return fail(error) }
            guard let tempURL, (response as? HTTPURLResponse)?.statusCode == 200 else {
                return fail(UpdateError.badResponse)
            }

            do {
                let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("HotCornersUpdate-\(UUID().uuidString)")
                let unpacked = workDir.appendingPathComponent("unpacked")
                try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)

                let zipURL = workDir.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: tempURL, to: zipURL)

                try unzip(zipURL, into: unpacked)

                guard let newApp = try FileManager.default
                    .contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" })
                else { throw UpdateError.appNotFoundInArchive }

                DispatchQueue.main.async {
                    swapAndRelaunch(newApp: newApp, workDir: workDir)
                    completion(nil)
                }
            } catch {
                fail(error)
            }
        }.resume()
    }

    private static func unzip(_ zip: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.unpackFailed(String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)")
        }
    }

    private static func swapAndRelaunch(newApp: URL, workDir: URL) {
        let destination = Bundle.main.bundleURL
        let script = workDir.appendingPathComponent("install.sh")

        // Paths travel through the environment so spaces in "Hot Corners.app" can't break quoting.
        let body = """
        #!/bin/sh
        while kill -0 "$HC_PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        rm -rf "$HC_DEST" || exit 1
        /usr/bin/ditto "$HC_SRC" "$HC_DEST" || exit 1
        /usr/bin/xattr -dr com.apple.quarantine "$HC_DEST" 2>/dev/null
        /usr/bin/open "$HC_DEST"
        rm -rf "$HC_TMP"
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = [
            "HC_PID": String(ProcessInfo.processInfo.processIdentifier),
            "HC_SRC": newApp.path,
            "HC_DEST": destination.path,
            "HC_TMP": workDir.path,
        ]
        try? process.run()

        NSApp.terminate(nil)
    }
}
