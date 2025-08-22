import Foundation

class TestFixtures {
    static let shared = TestFixtures()

    private init() {}

    lazy var testBundle: Bundle = {
        Bundle(for: type(of: self))
    }()

    var fixturesPath: String {
        guard let path = testBundle.path(forResource: "fixtures", ofType: nil) else {
            let projectPath = ProcessInfo.processInfo.environment["PROJECT_DIR"]
                ?? "/Users/luke/Code/@banjerluke/capacitor-meteor-webapp"
            return "\(projectPath)/tests/fixtures"
        }
        return path
    }

    func loadBundledWWWContent() -> [String: String] {
        var content: [String: String] = [:]
        let bundledWWWPath = "\(fixturesPath)/bundled_www"

        content["cordova_plugins.js"] = loadFileContent(path: "\(bundledWWWPath)/cordova_plugins.js")
        content["index.html"] = loadDefaultIndexContent()

        return content
    }

    func loadDownloadableVersion(_ version: String) -> [String: Any]? {
        let versionPath = "\(fixturesPath)/downloadable_versions/\(version)"

        guard let manifestData = loadFileData(path: "\(versionPath)/manifest.json") else {
            return nil
        }

        do {
            let manifest = try JSONSerialization.jsonObject(with: manifestData, options: []) as? [String: Any]
            return manifest
        } catch {
            print("Error loading manifest for version \(version): \(error)")
            return nil
        }
    }

    func loadAssetContent(version: String, assetPath: String) -> String? {
        let fullPath = "\(fixturesPath)/downloadable_versions/\(version)/\(assetPath)"
        return loadFileContent(path: fullPath)
    }

    func createTempDirectory() -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorMeteorWebAppTests")
            .appendingPathComponent(UUID().uuidString)

        try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
        return tempURL
    }

    func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func createMockBundleStructure(at baseURL: URL, version: String = "version1") {
        // Create program.json (the manifest format that AssetBundle expects)
        let programManifest: [String: Any] = [
            "format": "web-program-pre1",
            "version": version,
            "cordovaCompatibilityVersions": [
                "ios": "1.0.0"
            ],
            "manifest": [
                [
                    "path": "index.html",
                    "url": "/",
                    "type": "html",
                    "hash": "index-hash-\(version)",
                    "cacheable": false,
                    "where": "client"
                ],
                [
                    "path": "app/some-file",
                    "url": "/some-file",
                    "type": "js",
                    "hash": "some-file-hash-\(version)",
                    "cacheable": true,
                    "where": "client"
                ],
                [
                    "path": "cordova_plugins.js",
                    "url": "/cordova_plugins.js",
                    "type": "js",
                    "hash": "cordova-plugins-hash-\(version)",
                    "cacheable": true,
                    "where": "client"
                ]
            ]
        ]

        let programURL = baseURL.appendingPathComponent("program.json")
        let indexURL = baseURL.appendingPathComponent("index.html")
        let someFileURL = baseURL.appendingPathComponent("app/some-file")
        let cordovaPluginsURL = baseURL.appendingPathComponent("cordova_plugins.js")

        try? FileManager.default.createDirectory(at: baseURL.appendingPathComponent("app"),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)

        do {
            let programData = try JSONSerialization.data(withJSONObject: programManifest, options: .prettyPrinted)
            try programData.write(to: programURL)

            // Create index.html with embedded meteor runtime config
            let runtimeConfig = [
                "ROOT_URL": "http://localhost:3000",
                "appId": "test-app-id",
                "autoupdateVersionCordova": "1.0.0"
            ]
            let configData = try JSONSerialization.data(withJSONObject: runtimeConfig, options: [])
            let configString = String(data: configData, encoding: .utf8)!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

            let indexContent = """
            <html>
            <head>
                <title>Test App \(version)</title>
                <script type="text/javascript">
                    __meteor_runtime_config__ = JSON.parse(decodeURIComponent("\(configString)"));
                </script>
            </head>
            <body>Version \(version)</body>
            </html>
            """
            try indexContent.write(to: indexURL, atomically: true, encoding: .utf8)

            let someFileContent = "some-file content \(version)"
            try someFileContent.write(to: someFileURL, atomically: true, encoding: .utf8)

            let cordovaContent = loadDefaultCordovaPluginsContent()
            try cordovaContent.write(to: cordovaPluginsURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating mock bundle structure: \(error)")
        }
    }

    private func loadDefaultIndexContent() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Test Meteor App</title>
            <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>
            <div id="app">Loading...</div>
            <script type="text/javascript" src="cordova.js"></script>
        </body>
        </html>
        """
    }

    private func loadDefaultCordovaPluginsContent() -> String {
        return """
        cordova.define('cordova/plugin_list', function(require, exports, module) {
            module.exports = [];
            module.exports.metadata = {
                "cordova-plugin-meteor-webapp": "1.2.3"
            };
        });
        """
    }

    private func loadFileContent(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func loadFileData(path: String) -> Data? {
        return FileManager.default.contents(atPath: path)
    }

    // MARK: - Version Update Testing Support

    func createManifestJSON(version: String, changedFiles: [String] = []) -> Data? {
        let manifest: [String: Any] = [
            "format": "web-program-pre1",
            "version": version,
            "cordovaCompatibilityVersions": [
                "ios": "1.0.0"
            ],
            "manifest": createManifestEntries(version: version, changedFiles: changedFiles)
        ]

        do {
            return try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        } catch {
            print("Error creating manifest JSON: \(error)")
            return nil
        }
    }

    private func createManifestEntries(version: String, changedFiles: [String]) -> [[String: Any]] {
        var entries: [[String: Any]] = [
            [
                "path": "index.html",
                "url": "/",
                "type": "html",
                "hash": "index-hash-\(version)",
                "cacheable": false,
                "where": "client"
            ],
            [
                "path": "app/some-file",
                "url": "/some-file",
                "type": "js",
                "hash": "some-file-hash-\(version)",
                "cacheable": true,
                "where": "client"
            ]
        ]

        // Add changed files to manifest
        for changedFile in changedFiles {
            entries.append([
                "path": "app/\(changedFile)",
                "url": "/\(changedFile)",
                "type": "js",
                "hash": "\(changedFile)-hash-\(version)",
                "cacheable": true,
                "where": "client"
            ])
        }

        return entries
    }
}
