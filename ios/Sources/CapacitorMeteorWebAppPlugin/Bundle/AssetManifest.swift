import Foundation

/// Represents the manifest file (program.json) that describes all assets in a Meteor app bundle
public struct AssetManifest {

    /// A single entry in the asset manifest
    public struct Entry {
        public let filePath: String
        public let urlPath: String
        public let fileType: String
        public let cacheable: Bool
        public let hash: String?
        public let sourceMapPath: String?
        public let sourceMapURLPath: String?

        public init(filePath: String, urlPath: String, fileType: String,
                    cacheable: Bool, hash: String?,
                    sourceMapPath: String? = nil, sourceMapURLPath: String? = nil) {
            self.filePath = filePath
            self.urlPath = urlPath
            self.fileType = fileType
            self.cacheable = cacheable
            self.hash = hash
            self.sourceMapPath = sourceMapPath
            self.sourceMapURLPath = sourceMapURLPath
        }
    }

    public let version: String
    public let cordovaCompatibilityVersion: String
    public var entries: [Entry]

    /// Initialize from a manifest file URL
    public init(fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        try self.init(data: data)
    }

    /// Initialize from manifest data
    public init(data: Data) throws {
        let json: JSONObject
        do {
            json = try JSONSerialization.jsonObject(with: data, options: []) as! JSONObject
        } catch {
            throw WebAppError.invalidAssetManifest(reason: "Error parsing asset manifest", underlyingError: error)
        }

        // Check format compatibility
        if let format = json["format"] as? String, format != "web-program-pre1" {
            throw WebAppError.invalidAssetManifest(reason: "The asset manifest format is incompatible: \(format)", underlyingError: nil)
        }

        // Extract version
        guard let version = json["version"] as? String else {
            throw WebAppError.invalidAssetManifest(reason: "Asset manifest does not have a version", underlyingError: nil)
        }
        self.version = version

        // Extract Cordova compatibility version
        guard let cordovaCompatibilityVersions = json["cordovaCompatibilityVersions"] as? JSONObject,
              let cordovaCompatibilityVersion = cordovaCompatibilityVersions["ios"] as? String else {
            throw WebAppError.invalidAssetManifest(reason: "Asset manifest does not have a cordovaCompatibilityVersion", underlyingError: nil)
        }
        self.cordovaCompatibilityVersion = cordovaCompatibilityVersion

        // Parse manifest entries
        let entriesJSON = json["manifest"] as? [JSONObject] ?? []
        entries = []

        for entryJSON in entriesJSON {
            // Only process client-side assets
            guard entryJSON["where"] as? String == "client" else { continue }

            // Extract required fields
            guard let urlPath = entryJSON["url"] as? String,
                  let filePath = entryJSON["path"] as? String,
                  let fileType = entryJSON["type"] as? String,
                  let hash = entryJSON["hash"] as? String,
                  let cacheable = entryJSON["cacheable"] as? Bool else {
                continue
            }

            // Extract optional source map fields
            let sourceMapPath = entryJSON["sourceMap"] as? String
            let sourceMapURLPath = entryJSON["sourceMapUrl"] as? String

            let entry = Entry(
                filePath: filePath,
                urlPath: urlPath,
                fileType: fileType,
                cacheable: cacheable,
                hash: hash,
                sourceMapPath: sourceMapPath,
                sourceMapURLPath: sourceMapURLPath
            )
            entries.append(entry)
        }
    }
}
