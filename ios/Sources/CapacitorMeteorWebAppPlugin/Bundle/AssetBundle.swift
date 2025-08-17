import Foundation

/// Load the runtime config by extracting and parsing
/// `__meteor_runtime_config__` from index.html
func loadRuntimeConfigFromIndexFileAtURL(_ url: URL) throws -> AssetBundle.RuntimeConfig {
    do {
        let indexFileString = try String(contentsOf: url, encoding: .utf8)

        // Regex used to extract __meteor_runtime_config__ from index.html
        let configJSONRegEx = try NSRegularExpression(
            pattern: "__meteor_runtime_config__ = JSON.parse\\(decodeURIComponent\\(\"([^\"]*)\"\\)\\)",
            options: []
        )

        let nsString = indexFileString as NSString
        let range = NSRange(location: 0, length: nsString.length)

        guard let match = configJSONRegEx.firstMatch(in: indexFileString, options: [], range: range),
              let configString = nsString.substring(with: match.range(at: 1)).removingPercentEncoding,
              let configData = configString.data(using: .utf8) else {
            throw WebAppError.unsuitableAssetBundle(reason: "Couldn't load runtime config from index file", underlyingError: nil)
        }

        let json = try JSONSerialization.jsonObject(with: configData, options: []) as! JSONObject
        return AssetBundle.RuntimeConfig(json: json)
    } catch {
        throw WebAppError.unsuitableAssetBundle(reason: "Couldn't load runtime config from index file", underlyingError: error)
    }
}

/// Represents a complete version of the Meteor app with its files and manifest
public final class AssetBundle {
    private(set) var directoryURL: URL

    public let version: String
    public let cordovaCompatibilityVersion: String

    private var parentAssetBundle: AssetBundle?
    private var ownAssetsByURLPath: [String: Asset] = [:]
    private(set) var indexFile: Asset?

    public var ownAssets: [Asset] {
        return Array(ownAssetsByURLPath.values)
    }

    /// Initialize from a directory containing program.json
    public convenience init(directoryURL: URL, parentAssetBundle: AssetBundle? = nil) throws {
        let manifestURL = directoryURL.appendingPathComponent("program.json")
        let manifest = try AssetManifest(fileURL: manifestURL)
        try self.init(directoryURL: directoryURL, manifest: manifest, parentAssetBundle: parentAssetBundle)
    }

    /// Initialize with a specific manifest
    public init(directoryURL: URL, manifest: AssetManifest, parentAssetBundle: AssetBundle? = nil) throws {
        self.directoryURL = directoryURL
        self.parentAssetBundle = parentAssetBundle
        self.version = manifest.version
        self.cordovaCompatibilityVersion = manifest.cordovaCompatibilityVersion

        // Process manifest entries to create assets
        for entry in manifest.entries {
            let urlPath = URLPathByRemovingQueryString(entry.urlPath)

            // Only create asset if parent bundle doesn't already have it cached
            if parentAssetBundle?.cachedAssetForURLPath(urlPath, hash: entry.hash) == nil {
                let asset = Asset(
                    bundle: self,
                    filePath: entry.filePath,
                    urlPath: urlPath,
                    fileType: entry.fileType,
                    cacheable: entry.cacheable,
                    hash: entry.hash,
                    sourceMapURLPath: entry.sourceMapURLPath
                )
                addAsset(asset)
            }

            // Handle source maps
            if let sourceMapPath = entry.sourceMapPath,
               let sourceMapURLPath = entry.sourceMapURLPath {
                if parentAssetBundle?.cachedAssetForURLPath(sourceMapURLPath) == nil {
                    let sourceMapAsset = Asset(
                        bundle: self,
                        filePath: sourceMapPath,
                        urlPath: sourceMapURLPath,
                        fileType: "json",
                        cacheable: true
                    )
                    addAsset(sourceMapAsset)
                }
            }
        }

        // Add index.html asset
        let indexAsset = Asset(
            bundle: self,
            filePath: "index.html",
            urlPath: "/",
            fileType: "html",
            cacheable: false,
            hash: nil
        )
        addAsset(indexAsset)
        self.indexFile = indexAsset
    }

    /// Add an asset to this bundle
    public func addAsset(_ asset: Asset) {
        ownAssetsByURLPath[asset.urlPath] = asset
    }

    /// Find an asset by URL path, checking parent bundles if needed
    public func assetForURLPath(_ urlPath: String) -> Asset? {
        return ownAssetsByURLPath[urlPath] ?? parentAssetBundle?.assetForURLPath(urlPath)
    }

    /// Check if asset exists in this bundle (not including parent)
    public func assetExistsInBundle(_ urlPath: String) -> Bool {
        return ownAssetsByURLPath[urlPath] != nil
    }

    /// Get cached asset if it exists and matches the hash (for reuse)
    public func cachedAssetForURLPath(_ urlPath: String, hash: String? = nil) -> Asset? {
        if let asset = ownAssetsByURLPath[urlPath],
           // If the asset is not cacheable, we require a matching hash
           (asset.cacheable || asset.hash != nil) && asset.hash == hash {
            return asset
        }
        return nil
    }

    /// Update the directory URL when bundle is moved
    public func didMoveToDirectoryAtURL(_ url: URL) {
        self.directoryURL = url
    }

    // MARK: - Runtime Configuration

    /// Runtime configuration extracted from __meteor_runtime_config__ in index.html
    public struct RuntimeConfig {
        private let json: JSONObject

        public init(json: JSONObject) {
            self.json = json
        }

        public var appId: String? {
            return json["appId"] as? String
        }

        public var rootURL: URL? {
            if let rootURLString = json["ROOT_URL"] as? String {
                return URL(string: rootURLString)
            }
            return nil
        }

        public var autoupdateVersionCordova: String? {
            return json["autoupdateVersionCordova"] as? String
        }
    }

    /// Lazily loaded runtime config from index.html
    public lazy var runtimeConfig: RuntimeConfig? = {
        guard let indexFile = self.indexFile else { return nil }

        do {
            return try loadRuntimeConfigFromIndexFileAtURL(indexFile.fileURL)
        } catch {
            print("Error loading runtime config: \(error)")
            return nil
        }
    }()

    /// App ID from runtime config
    public var appId: String? {
        return runtimeConfig?.appId
    }

    /// Root URL from runtime config
    public var rootURL: URL? {
        return runtimeConfig?.rootURL
    }
}
