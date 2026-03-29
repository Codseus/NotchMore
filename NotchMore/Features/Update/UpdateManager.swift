import AppKit
import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var updateURL: URL?
    @Published var lastChecked: Date?
    @Published var isChecking: Bool = false
    @Published var errorMessage: String?

    private let repoURL = "https://api.github.com/repos/Codseus/NotchMore/releases/latest"

    private init() {}

    func checkForUpdates(manual: Bool = false) {
        guard let url = URL(string: repoURL) else { return }

        DispatchQueue.main.async {
            self.isChecking = true
            self.errorMessage = nil
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                self?.lastChecked = Date()
            }

            if let error = error {
                DispatchQueue.main.async {
                    if manual {
                        self?.errorMessage =
                            "Error checking for updates: \(error.localizedDescription)"
                    }
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                DispatchQueue.main.async {
                    if manual {
                        self?.errorMessage = "No releases found yet."
                    }
                }
                return
            }

            guard let data = data else { return }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let currentVersion =
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

                DispatchQueue.main.async {
                    if self?.isVersion(release.tagName, newerThan: currentVersion) == true {
                        self?.isUpdateAvailable = true
                        self?.latestVersion = release.tagName
                        self?.releaseNotes = release.body
                        self?.updateURL = URL(string: release.htmlUrl)
                    } else if manual {
                        self?.errorMessage = "You're up to date! (Version \(currentVersion))"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if manual { self?.errorMessage = "Failed to parse update information." }
                }
                print("Update check error: \(error)")
            }
        }
        task.resume()
    }

    func downloadUpdate() {
        if let url = updateURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func isVersion(_ newVersion: String, newerThan currentVersion: String) -> Bool {
        let new = newVersion.replacingOccurrences(of: "v", with: "").split(separator: ".")
            .compactMap { Int($0) }
        let current = currentVersion.replacingOccurrences(of: "v", with: "").split(separator: ".")
            .compactMap { Int($0) }

        for i in 0..<min(new.count, current.count) {
            if new[i] > current[i] { return true }
            if new[i] < current[i] { return false }
        }

        return new.count > current.count
    }
}
