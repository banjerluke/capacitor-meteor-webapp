import Foundation

/// Handles file organization logic for bundles, including URL path mapping and directory structure creation
public class BundleOrganizer {

    /// Organizes files in a bundle directory according to their URL mappings
    /// - Parameters:
    ///   - bundle: The asset bundle to organize
    ///   - targetDirectory: The directory where files should be organized
    /// - Throws: WebAppError if organization fails
    static func organizeBundle(_ bundle: AssetBundle, in targetDirectory: URL) throws {
        let fileManager = FileManager.default

        // Create target directory if it doesn't exist
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)

        for asset in bundle.ownAssets {
            try organizeAsset(asset, in: targetDirectory, fileManager: fileManager)
        }
    }

    /// Organizes a single asset according to its URL path mapping
    /// - Parameters:
    ///   - asset: The asset to organize
    ///   - targetDirectory: The target directory
    ///   - fileManager: File manager instance
    /// - Throws: WebAppError if organization fails
    private static func organizeAsset(_ asset: Asset, in targetDirectory: URL, fileManager: FileManager) throws {
        let sourceURL = asset.fileURL
        let targetURL = targetURLForAsset(asset, in: targetDirectory)

        print("📁 Organizing asset:")
        print("   URL path: \(asset.urlPath)")
        print("   File path: \(asset.filePath)")
        print("   Source URL: \(sourceURL.path)")
        print("   Target URL: \(targetURL.path)")

        // Ensure the target directory structure exists
        let targetDirectoryURL = targetURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        // Check if source file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            // Skip missing source map and TypeScript declaration files silently (they may be excluded)
            if asset.urlPath.hasSuffix(".map") || asset.fileURL.pathExtension == "map" {
                print("DEBUG: Skipping missing source map file: \(asset.urlPath)")
                return
            }
            if asset.urlPath.hasSuffix(".d.ts") || asset.fileURL.pathExtension == "d.ts" {
                print("DEBUG: Skipping missing TypeScript declaration file: \(asset.urlPath)")
                return
            }
            print("❌ Source file missing - Asset: \(asset.urlPath), Expected path: \(sourceURL.path)")
            throw WebAppError.fileSystemError(reason: "Source file does not exist: \(sourceURL.path)", underlyingError: nil)
        }

        // If target already exists, remove it first
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        // Try to create hard link first (for efficiency), fall back to copy
        do {
            try fileManager.linkItem(at: sourceURL, to: targetURL)
        } catch {
            // Hard link failed, try copying instead
            do {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            } catch {
                throw WebAppError.fileSystemError(reason: "Failed to organize asset \(asset.urlPath)", underlyingError: error)
            }
        }
    }

    /// Calculates the target URL for an asset based on its URL path mapping
    /// - Parameters:
    ///   - asset: The asset
    ///   - targetDirectory: The target directory
    /// - Returns: The URL where the asset should be placed
    static func targetURLForAsset(_ asset: Asset, in targetDirectory: URL) -> URL {
        // Remove leading slash from URL path to make it relative
        var relativePath = asset.urlPath
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }

        // Handle root path (/) -> index.html
        if relativePath.isEmpty {
            relativePath = "index.html"
        }

        return targetDirectory.appendingPathComponent(relativePath)
    }

    /// Creates the directory structure needed for a bundle's URL mappings
    /// - Parameters:
    ///   - bundle: The bundle to analyze
    ///   - targetDirectory: The target directory
    /// - Throws: WebAppError if directory creation fails
    static func createDirectoryStructure(for bundle: AssetBundle, in targetDirectory: URL) throws {
        let fileManager = FileManager.default

        // Create the target directory itself
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)

        // Get all unique directory paths from assets
        let directoryPaths = Set(bundle.ownAssets.compactMap { asset -> String? in
            let targetURL = targetURLForAsset(asset, in: targetDirectory)
            let directoryURL = targetURL.deletingLastPathComponent()
            return directoryURL.path
        })

        // Create all required directories
        for directoryPath in directoryPaths {
            let directoryURL = URL(fileURLWithPath: directoryPath)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Validates that all assets in a bundle can be properly organized
    /// - Parameter bundle: The bundle to validate
    /// - Returns: Array of validation errors (empty if valid)
    static func validateBundleOrganization(_ bundle: AssetBundle) -> [String] {
        var errors: [String] = []
        var urlPaths: Set<String> = []

        for asset in bundle.ownAssets {
            // Check for duplicate URL paths
            if urlPaths.contains(asset.urlPath) {
                errors.append("Duplicate URL path: \(asset.urlPath)")
            } else {
                urlPaths.insert(asset.urlPath)
            }

            // Check for invalid characters in URL path
            if asset.urlPath.contains("..") {
                errors.append("Invalid URL path contains '..': \(asset.urlPath)")
            }
        }

        return errors
    }

    /// Removes organized files from a target directory
    /// - Parameter targetDirectory: Directory to clean up
    /// - Throws: WebAppError if cleanup fails
    public static func cleanupOrganizedBundle(at targetDirectory: URL) throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: targetDirectory.path) else {
            return // Nothing to clean up
        }

        do {
            try fileManager.removeItem(at: targetDirectory)
        } catch {
            throw WebAppError.fileSystemError(reason: "Failed to cleanup bundle directory", underlyingError: error)
        }
    }
}
