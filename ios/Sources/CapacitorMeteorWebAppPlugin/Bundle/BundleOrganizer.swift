//
// BundleOrganizer.swift
//
// Handles file organization logic for bundles, including URL path mapping
// and directory structure creation for Meteor webapp assets.
//

import Foundation

/// Handles file organization logic for bundles, including URL path mapping and directory structure creation
public class BundleOrganizer {

    /// Organizes files in a bundle directory according to their URL mappings
    /// - Parameters:
    ///   - bundle: The asset bundle to organize
    ///   - targetDirectory: The directory where files should be organized
    /// - Throws: WebAppError if organization fails
    static func organizeBundle(_ bundle: AssetBundle, in targetDirectory: URL) throws {
        // Validate bundle before any file operations to prevent path traversal
        // and duplicate URL attacks from malicious manifests
        let validationErrors = validateBundleOrganization(bundle)
        if !validationErrors.isEmpty {
            throw WebAppError.unsuitableAssetBundle(
                reason: "Bundle validation failed: \(validationErrors.joined(separator: "; "))",
                underlyingError: nil)
        }

        let fileManager = FileManager.default

        // Create target directory if it doesn't exist
        try fileManager.createDirectory(
            at: targetDirectory, withIntermediateDirectories: true, attributes: nil)

        // Organize own assets
        for asset in bundle.ownAssets {
            try organizeAsset(asset, in: targetDirectory, fileManager: fileManager)
        }

        // Also organize parent assets that this bundle inherits but doesn't override
        var inheritedAssetsOrganized = 0
        if let parentBundle = bundle.parentAssetBundle {
            for parentAsset in parentBundle.ownAssets {
                // Only organize parent assets that we don't have in our own assets
                if bundle.ownAssetsByURLPath[parentAsset.urlPath] == nil {
                    try organizeAsset(parentAsset, in: targetDirectory, fileManager: fileManager)
                    inheritedAssetsOrganized += 1
                }
            }
        }
    }

    /// Organizes a single asset according to its URL path mapping
    /// - Parameters:
    ///   - asset: The asset to organize
    ///   - targetDirectory: The target directory
    ///   - fileManager: File manager instance
    /// - Throws: WebAppError if organization fails
    private static func organizeAsset(
        _ asset: Asset, in targetDirectory: URL, fileManager: FileManager
    ) throws {
        let sourceURL = asset.fileURL
        let targetURL = targetURLForAsset(asset, in: targetDirectory)

        // Ensure the target directory structure exists
        let targetDirectoryURL = targetURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: targetDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        // Check if source file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            if asset.urlPath.hasSuffix(".map") || asset.fileURL.pathExtension == "map" {
                // Skip missing source maps - they may not be served in production
                return
            }
            print(
                "❌ Source file missing - Asset: \(asset.urlPath), Expected path: \(sourceURL.path)")
            throw WebAppError.fileSystemError(
                reason: "Source file does not exist: \(sourceURL.path)", underlyingError: nil)
        }

        // If target already exists, remove it first
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        if asset.urlPath == "/" || asset.urlPath == "/index.html"

            || sourceURL.lastPathComponent == "index.html" {
            // Special handling for index.html - inject WebAppLocalServer shim
            try organizeIndexHtml(sourceURL: sourceURL, targetURL: targetURL)
        } else {
            // Try to create hard link first (for efficiency), fall back to copy
            do {
                try fileManager.linkItem(at: sourceURL, to: targetURL)
            } catch {
                // Hard link failed, try copying instead
                do {
                    try fileManager.copyItem(at: sourceURL, to: targetURL)
                } catch {
                    throw WebAppError.fileSystemError(
                        reason: "Failed to organize asset \(asset.urlPath)", underlyingError: error)
                }
            }
        }
    }

    /// Special handling for index.html files to inject WebAppLocalServer shim
    /// - Parameters:
    ///   - sourceURL: Source index.html file
    ///   - targetURL: Target location for the modified index.html
    /// - Throws: WebAppError if processing fails
    private static func organizeIndexHtml(sourceURL: URL, targetURL: URL) throws {
        // Read the original HTML content
        let originalContent: String
        do {
            originalContent = try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw WebAppError.fileSystemError(
                reason: "Failed to read index.html content", underlyingError: error)
        }

        // WebAppLocalServer compatibility shim for Capacitor
        // Provides the same API as cordova-plugin-meteor-webapp
        let shimScript = """
            <script>
            (function() {
                if (window.WebAppLocalServer) return;

                if (window.Capacitor) {
                    setupWebAppLocalServer();
                } else {
                    document.addEventListener('deviceready', function() {
                        setupWebAppLocalServer();
                    });
                }

                function setupWebAppLocalServer() {
                    const P = ((window.Capacitor || {}).Plugins || {}).CapacitorMeteorWebApp;
                    if (!P) {
                        throw new Error('WebAppLocalServer shim: CapacitorMeteorWebApp plugin not available');
                    }

                    window.WebAppLocalServer = {
                        startupDidComplete(callback) {
                            P.startupDidComplete()
                            .then(() => { if (callback) callback(); })
                            .catch((error) => { console.error('WebAppLocalServer.startupDidComplete() failed:', error); });
                        },

                        checkForUpdates(callback) {
                            P.checkForUpdates()
                            .then(() => { if (callback) callback(); })
                            .catch((error) => { console.error('WebAppLocalServer.checkForUpdates() failed:', error); });
                        },

                        onNewVersionReady(callback) {
                            P.addListener('updateAvailable', callback);
                        },

                        switchToPendingVersion(callback, errorCallback) {
                            P.reload()
                            .then(() => { if (callback) callback(); })
                            .catch((error) => {
                                console.error('switchToPendingVersion failed:', error);
                                if (typeof errorCallback === 'function') errorCallback(error);
                            });
                        },

                        onError(callback) {
                            P.addListener('error', (event) => {
                                const error = new Error(event.message || 'Unknown CapacitorMeteorWebApp error');
                                callback(error);
                            });
                        },

                        localFileSystemUrl(_fileUrl) {
                            throw new Error('Local filesystem URLs not supported by Capacitor');
                        },
                    };
                }
            })();
            </script>
        """

        // Inject the shim before closing </head> tag, or before </body> if no head
        let modifiedContent: String
        if let headCloseRange = originalContent.range(of: "</head>", options: .caseInsensitive) {
            modifiedContent = originalContent.replacingCharacters(in: headCloseRange, with: shimScript + "\n</head>")
        } else if let bodyCloseRange = originalContent.range(of: "</body>", options: .caseInsensitive) {
            modifiedContent = originalContent.replacingCharacters(in: bodyCloseRange, with: shimScript + "\n</body>")
        } else {
            // Just append to the end if we can't find head or body tags
            modifiedContent = originalContent + shimScript
        }

        do {
            try modifiedContent.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            throw WebAppError.fileSystemError(reason: "Failed to write modified index.html", underlyingError: error)
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
        try fileManager.createDirectory(
            at: targetDirectory, withIntermediateDirectories: true, attributes: nil)

        // Get all unique directory paths from assets
        let directoryPaths = Set(
            bundle.ownAssets.compactMap { asset -> String? in
                let targetURL = targetURLForAsset(asset, in: targetDirectory)
                let directoryURL = targetURL.deletingLastPathComponent()
                return directoryURL.path
            })

        // Create all required directories
        for directoryPath in directoryPaths {
            let directoryURL = URL(fileURLWithPath: directoryPath)
            try fileManager.createDirectory(
                at: directoryURL, withIntermediateDirectories: true, attributes: nil)
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
            return  // Nothing to clean up
        }

        do {
            try fileManager.removeItem(at: targetDirectory)
        } catch {
            throw WebAppError.fileSystemError(
                reason: "Failed to cleanup bundle directory", underlyingError: error)
        }
    }
}
