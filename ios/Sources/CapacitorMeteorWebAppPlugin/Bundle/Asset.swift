import Foundation

/// Represents a single asset file within a Meteor app bundle
public struct Asset {
    public let bundle: AssetBundle
    public let filePath: String
    public let urlPath: String
    public let fileType: String?
    public let cacheable: Bool
    public let hash: String?
    public let sourceMapURLPath: String?

    /// The file URL for this asset within the bundle directory
    public var fileURL: URL {
        return bundle.directoryURL.appendingPathComponent(filePath, isDirectory: false)
    }

    public init(bundle: AssetBundle, filePath: String, urlPath: String,
                fileType: String? = nil, cacheable: Bool, hash: String? = nil,
                sourceMapURLPath: String? = nil) {
        self.bundle = bundle
        self.filePath = filePath
        self.urlPath = urlPath
        self.fileType = fileType
        self.cacheable = cacheable
        self.hash = hash
        self.sourceMapURLPath = sourceMapURLPath
    }
}

// MARK: - CustomStringConvertible

extension Asset: CustomStringConvertible {
    public var description: String {
        return urlPath
    }
}

// MARK: - Hashable & Equatable

extension Asset: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(bundle))
        hasher.combine(urlPath)
    }
}

extension Asset: Equatable {
    public static func ==(lhs: Asset, rhs: Asset) -> Bool {
        return ObjectIdentifier(lhs.bundle) == ObjectIdentifier(rhs.bundle) &&
            lhs.urlPath == rhs.urlPath
    }
}
