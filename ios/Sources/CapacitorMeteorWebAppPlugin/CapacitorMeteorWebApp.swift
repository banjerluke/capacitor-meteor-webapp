import Foundation
import WebKit
import os.log

// Protocol for Capacitor bridge to avoid direct dependency
public protocol CapacitorBridge: AnyObject {
    func setServerBasePath(_ path: String)
    func getWebView() -> AnyObject?
    var webView: WKWebView? { get }
    func reload()
}

@available(iOS 13.0, *)
@objc public class CapacitorMeteorWebApp: NSObject, AssetBundleManagerDelegate {

    // MARK: - Properties

    /// Persistent configuration settings for the webapp
    private(set) var configuration: WebAppConfiguration!

    /// The asset bundle manager handles downloading and managing bundles
    private(set) var assetBundleManager: AssetBundleManager!

    /// The asset bundle currently used to serve assets from
    private var currentAssetBundle: AssetBundle! {
        didSet {
            updateConfigurationWithCurrentBundle()
        }
    }

    /// Downloaded asset bundles are considered pending until the next page reload
    /// because we don't want the app to end up in an inconsistent state by
    /// loading assets from different bundles.
    private var pendingAssetBundle: AssetBundle?

    /// Timer used to wait for startup to complete after a reload
    private var startupTimer: Timer?

    /// The number of seconds to wait for startup to complete, after which
    /// we revert to the last known good version
    private var startupTimeoutInterval: TimeInterval = 30.0

    /// Serial queue to prevent concurrent bundle switches
    private let bundleSwitchQueue = DispatchQueue(
        label: "com.meteor.webapp.bundle-switch", qos: .userInitiated)

    /// Logger for this module
    private let logger = os.Logger(
        subsystem: "com.meteor.webapp", category: "CapacitorMeteorWebApp")

    /// The www directory in the app bundle
    private var wwwDirectoryURL: URL!

    /// Reference to Capacitor bridge for bundle switching
    private weak var capacitorBridge: CapacitorBridge?

    /// Track if we switched to a new version (for startup timer)
    private var switchedToNewVersion = false

    /// Directory for serving organized bundles
    private var servingDirectoryURL: URL!

    // MARK: - Initialization

    public init(capacitorBridge: CapacitorBridge? = nil) {
        super.init()

        self.capacitorBridge = capacitorBridge

        // Initialize configuration
        configuration = WebAppConfiguration()

        // Set www directory URL - check if it exists first
        guard let resourceURL = Bundle.main.resourceURL else {
            logger.error("Could not get main bundle resource URL")
            return
        }

        // Capacitor typically uses 'public' but fall back to 'www' if needed
        let publicURL = resourceURL.appendingPathComponent("public")
        let wwwURL = resourceURL.appendingPathComponent("www")

        if FileManager.default.fileExists(atPath: publicURL.path) {
            wwwDirectoryURL = publicURL
        } else if FileManager.default.fileExists(atPath: wwwURL.path) {
            wwwDirectoryURL = wwwURL
            logger.info("Using www directory instead of public")
        } else {
            logger.error("Neither public nor www directory exists in bundle")
            return
        }

        // Initialize asset bundles
        do {
            try initializeAssetBundles()
        } catch {
            logger.error("Failed to initialize asset bundles: \(error.localizedDescription)")
        }

        // Setup startup timer
        setupStartupTimer()
    }

    private func initializeAssetBundles() throws {
        assetBundleManager = nil

        // The initial asset bundle consists of the assets bundled with the app
        guard let wwwURL = wwwDirectoryURL else {
            throw HotCodePushError.initializationFailed(reason: "www directory URL not set")
        }

        let initialAssetBundle: AssetBundle
        do {
            initialAssetBundle = try AssetBundle(directoryURL: wwwURL)
        } catch {
            throw HotCodePushError.initializationFailed(
                reason: "Could not load initial asset bundle: \(error.localizedDescription)")
        }

        let fileManager = FileManager.default

        // Downloaded versions are stored in Library/NoCloud/meteor
        guard
            let libraryDirectoryURL = FileManager.default.urls(
                for: .libraryDirectory, in: .userDomainMask
            ).first
        else {
            throw HotCodePushError.initializationFailed(
                reason: "Could not get library directory URL")
        }
        let versionsDirectoryURL = libraryDirectoryURL.appendingPathComponent("NoCloud/meteor")

        // Serving directory for organized bundles
        servingDirectoryURL = libraryDirectoryURL.appendingPathComponent("NoCloud/meteor-serving")

        // If the last seen initial version is different from the currently bundled
        // version, we delete the versions directory and reset configuration
        if configuration.lastSeenInitialVersion != initialAssetBundle.version {
            do {
                if fileManager.fileExists(atPath: versionsDirectoryURL.path) {
                    try fileManager.removeItem(at: versionsDirectoryURL)
                }
                if fileManager.fileExists(atPath: servingDirectoryURL.path) {
                    try fileManager.removeItem(at: servingDirectoryURL)
                }
            } catch {
                logger.error("Could not remove versions directory: \(error.localizedDescription)")
            }

            configuration.reset()
        }

        // We keep track of the last seen initial version
        configuration.lastSeenInitialVersion = initialAssetBundle.version

        // Create directories if they don't exist
        do {
            if !fileManager.fileExists(atPath: versionsDirectoryURL.path) {
                try fileManager.createDirectory(
                    at: versionsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            if !fileManager.fileExists(atPath: servingDirectoryURL.path) {
                try fileManager.createDirectory(
                    at: servingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            throw HotCodePushError.initializationFailed(
                reason: "Could not create directories: \(error.localizedDescription)")
        }

        assetBundleManager = AssetBundleManager(
            configuration: configuration, versionsDirectoryURL: versionsDirectoryURL,
            initialAssetBundle: initialAssetBundle)
        assetBundleManager.delegate = self

        // If a last downloaded version has been set and the asset bundle exists,
        // we set it as the current asset bundle
        if let lastDownloadedVersion = configuration.lastDownloadedVersion,
            let downloadedAssetBundle = assetBundleManager.downloadedAssetBundleWithVersion(
                lastDownloadedVersion)
        {
            currentAssetBundle = downloadedAssetBundle
            if configuration.lastKnownGoodVersion != lastDownloadedVersion {
                startStartupTimer()
            }
        } else {
            currentAssetBundle = initialAssetBundle
        }

        pendingAssetBundle = nil

        // Organize and serve the current bundle
        setupCurrentBundle()
    }

    private func setupStartupTimer() {
        startupTimer = Timer(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            self?.logger.error("App startup timed out, reverting to last known good version")
            self?.revertToLastKnownGoodVersion()
        }
    }

    private func updateConfigurationWithCurrentBundle() {
        guard let currentBundle = currentAssetBundle else { return }

        configuration.appId = currentBundle.appId
        configuration.rootURL = currentBundle.rootURL
        configuration.cordovaCompatibilityVersion = currentBundle.cordovaCompatibilityVersion
        logger.info("Serving asset bundle version: \(currentBundle.version)")
    }

    private func setupCurrentBundle() {
        guard let currentAssetBundle = currentAssetBundle else { return }

        do {
            let bundleServingDirectory = servingDirectoryURL.appendingPathComponent(
                currentAssetBundle.version)

            // Remove existing serving directory for this version
            if FileManager.default.fileExists(atPath: bundleServingDirectory.path) {
                try FileManager.default.removeItem(at: bundleServingDirectory)
            }

            // Organize the bundle for serving
            try BundleOrganizer.organizeBundle(currentAssetBundle, in: bundleServingDirectory)

            // Set Capacitor's server base path to serve from organized bundle
            setServerBasePath(bundleServingDirectory)

        } catch let webAppError as WebAppError {
            logger.error("Could not setup current bundle (WebAppError): \(webAppError.description)")
        } catch {
            logger.error("Could not setup current bundle: \(error.localizedDescription)")
        }
    }

    private func setServerBasePath(_ path: URL) {
        guard let bridge = capacitorBridge else {
            logger.error("No Capacitor bridge available for setting server base path")
            return
        }

        // Use Capacitor's setServerBasePath to change serving directory
        // Must be called on main thread
        DispatchQueue.main.async {
            bridge.setServerBasePath(path.path)
        }
    }

    private func startStartupTimer() {
        // Don't start the startup timer if the app started up in the background
        #if canImport(UIKit)
            if UIApplication.shared.applicationState == .active {
                logger.info("App startup timer started")
                startupTimer?.start(withTimeInterval: startupTimeoutInterval)
            }
        #else
            logger.info("App startup timer started")
            startupTimer?.start(withTimeInterval: startupTimeoutInterval)
        #endif
    }

    // MARK: - Public Methods

    /**
     * Check for available updates from the Meteor server
     */
    public func checkForUpdates(completion: @escaping (Error?) -> Void) {
        guard let rootURL = configuration.rootURL else {
            let error = HotCodePushError.noRootURLConfigured
            completion(error)
            return
        }

        let baseURL = rootURL.appendingPathComponent("__cordova/")
        assetBundleManager.checkForUpdatesWithBaseURL(baseURL)

        // Note: Actual completion will be called through delegate methods
        completion(nil)
    }

    /**
     * Check for available updates from the Meteor server (async version)
     */
    public func checkForUpdates() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            checkForUpdates { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /**
     * Notify the plugin that app startup is complete
     */
    public func startupDidComplete(completion: @escaping (Error?) -> Void) {
        logger.info("App startup confirmed")
        startupTimer?.stop()

        // If startup completed successfully, we consider a version good
        configuration.lastKnownGoodVersion = currentAssetBundle.version

        // Clean up old asset bundles in the background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.assetBundleManager.removeAllDownloadedAssetBundlesExceptFor(
                    self.currentAssetBundle)
            } catch {
                self.logger.error(
                    "Could not remove unused asset bundles: \(error.localizedDescription)")
            }
        }

        completion(nil)
    }

    /**
     * Notify the plugin that app startup is complete (async version)
     */
    public func startupDidComplete() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            startupDidComplete { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /**
     * Get the current app version
     */
    public func getCurrentVersion() -> String {
        return currentAssetBundle?.version ?? "unknown"
    }

    /**
     * Check if an update is available and ready to install
     */
    public func isUpdateAvailable() -> Bool {
        return pendingAssetBundle != nil
    }

    /**
     * Reload the app with the latest available version
     */
    public func reload(completion: @escaping (Error?) -> Void) {
        bundleSwitchQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(HotCodePushError.bridgeUnavailable)
                }
                return
            }

            self._performReload(completion: completion)
        }
    }

    private func _performReload(completion: @escaping (Error?) -> Void) {
        // If there is a pending asset bundle, we switch to it atomically
        guard let pendingAssetBundle = pendingAssetBundle else {
            DispatchQueue.main.async {
                completion(HotCodePushError.noPendingVersion)
            }
            return
        }

        logger.info("Switching to pending version \(pendingAssetBundle.version)")

        do {
            // Organize the pending bundle for serving
            let bundleServingDirectory = servingDirectoryURL.appendingPathComponent(
                pendingAssetBundle.version)

            // Remove existing serving directory for this version
            if FileManager.default.fileExists(atPath: bundleServingDirectory.path) {
                try FileManager.default.removeItem(at: bundleServingDirectory)
            }

            // Organize the bundle
            try BundleOrganizer.organizeBundle(pendingAssetBundle, in: bundleServingDirectory)

            // Make atomic switch
            currentAssetBundle = pendingAssetBundle
            self.pendingAssetBundle = nil
            switchedToNewVersion = true

            // Set new server base path (this will dispatch to main thread)
            setServerBasePath(bundleServingDirectory)

            // Reload the WebView (this will dispatch to main thread)
            reloadWebView()

            // Start startup timer to track successful loading
            startStartupTimer()

            DispatchQueue.main.async {
                completion(nil)
            }

        } catch {
            let hotCodePushError = HotCodePushError.bundleOrganizationFailed(
                reason: "Failed to organize bundle for version \(pendingAssetBundle.version)",
                underlyingError: error
            )
            DispatchQueue.main.async {
                completion(hotCodePushError)
            }
        }
    }

    /**
     * Reload the app with the latest available version (async version)
     */
    public func reload() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            reload { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func reloadWebView() {
        guard let bridge = capacitorBridge else {
            logger.error("Could not get Capacitor bridge for reload")
            return
        }

        DispatchQueue.main.async {
            // Prefer Capacitor's reload method if available, otherwise fall back to webView.reload()
            if let webView = bridge.webView {
                bridge.reload()
            } else {
                self.logger.error("Could not get WebView for reload")
            }
        }
    }

    // MARK: - Recovery and Error Handling

    private func revertToLastKnownGoodVersion() {
        bundleSwitchQueue.async { [weak self] in
            self?._performRevertToLastKnownGoodVersion()
        }
    }

    private func _performRevertToLastKnownGoodVersion() {

        // Blacklist the current version, so we don't update to it again right away
        configuration.addBlacklistedVersion(currentAssetBundle.version)

        // If there is a last known good version and we can load the bundle, revert to it
        if let lastKnownGoodVersion = configuration.lastKnownGoodVersion,
            let lastKnownGoodAssetBundle = assetBundleManager.downloadedAssetBundleWithVersion(
                lastKnownGoodVersion)
        {
            pendingAssetBundle = lastKnownGoodAssetBundle
            // Else, revert to the initial asset bundle, unless that is what we are currently serving
        } else if currentAssetBundle.version != assetBundleManager.initialAssetBundle.version {
            pendingAssetBundle = assetBundleManager.initialAssetBundle
        }

        // Only reload if we have a pending asset bundle to reload
        if pendingAssetBundle != nil {
            forceReload()
        } else {
            logger.warning("There is no last good version we can revert to")
        }
    }

    private func forceReload() {
        guard let bridge = capacitorBridge else {
            logger.error("Could not get Capacitor bridge for force reload")
            return
        }

        DispatchQueue.main.async {
            if let webView = bridge.webView {
                webView.reloadFromOrigin()
            } else {
                // Fallback to regular reload if webView is not available
                bridge.reload()
            }
        }
    }

    // MARK: - Lifecycle Handling

    public func onPageReload() {
        // If there is a pending asset bundle, we make it the current
        if let pendingAssetBundle = pendingAssetBundle {
            currentAssetBundle = pendingAssetBundle
            self.pendingAssetBundle = nil
        }

        if switchedToNewVersion {
            switchedToNewVersion = false
            startStartupTimer()
        }
    }

    public func onApplicationDidEnterBackground() {
        // Stop startup timer when going into the background, to avoid
        // blacklisting a version just because the web view has been suspended
        startupTimer?.stop()
    }

    // MARK: - AssetBundleManagerDelegate

    func assetBundleManager(
        _ assetBundleManager: AssetBundleManager,
        shouldDownloadBundleForManifest manifest: AssetManifest
    ) -> Bool {
        // No need to redownload the current or the pending version
        if currentAssetBundle.version == manifest.version
            || pendingAssetBundle?.version == manifest.version
        {
            return false
        }

        // Don't download blacklisted versions
        if configuration.blacklistedVersions.contains(manifest.version) {
            logger.info("Skipping blacklisted version: \(manifest.version)")
            return false
        }

        // Don't download versions potentially incompatible with the bundled native code
        if manifest.cordovaCompatibilityVersion != configuration.cordovaCompatibilityVersion {
            logger.info("Skipping incompatible version: \(manifest.version)")
            return false
        }

        return true
    }

    func assetBundleManager(
        _ assetBundleManager: AssetBundleManager,
        didFinishDownloadingBundle assetBundle: AssetBundle
    ) {
        logger.info("Finished downloading new asset bundle version: \(assetBundle.version)")

        configuration.lastDownloadedVersion = assetBundle.version
        pendingAssetBundle = assetBundle

        // Notify any listeners that a new version is ready
        notifyUpdateAvailable(version: assetBundle.version)
    }

    func assetBundleManager(
        _ assetBundleManager: AssetBundleManager, didFailDownloadingBundleWithError error: Error
    ) {
        logger.error("Download failure: \(error.localizedDescription)")
        notifyUpdateFailed(error: error)
    }

    // MARK: - Event Notifications

    private func notifyUpdateAvailable(version: String) {
        // Can be overridden by subclasses or used by plugin bridge
    }

    private func notifyUpdateFailed(error: Error) {
        // Can be overridden by subclasses or used by plugin bridge
    }
}
