//
// CapacitorMeteorWebApp.swift
//
// Core implementation of the Meteor webapp functionality for Capacitor,
// managing asset bundles, updates, and the web view integration.
//
// This is largely adapted from WebAppLocalServer.swift from the old
// cordova-plugin-meteor-webapp project. We don't embed our own web server
// any more, however; instead, we use Capacitor's built-in server.
//

import Foundation
import WebKit
import os.log

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Notification Names
extension Notification.Name {
    static let meteorWebappUpdateAvailable = Notification.Name("MeteorWebappUpdateAvailable")
    static let meteorWebappUpdateFailed = Notification.Name("MeteorWebappUpdateFailed")
}

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
    private(set) var configuration: WebAppConfiguration

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
    private var startupTimer: TimerInterface?

    /// The number of seconds to wait for startup to complete, after which
    /// we revert to the last known good version
    private var startupTimeoutInterval: TimeInterval = 30.0

    /// Serial queue to prevent concurrent bundle switches
    private let bundleSwitchQueue = DispatchQueue(
        label: "com.meteor.webapp.bundle-switch", qos: .userInitiated)

    /// Logger for this module
    private let logger = os.Logger(
        subsystem: "com.meteor.webapp", category: "CapacitorMeteorWebApp")

    /// Injected dependencies
    private let dependencies: CapacitorMeteorWebAppDependencies

    /// Track if we switched to a new version (for startup timer)
    private var switchedToNewVersion = false

    // MARK: - Initialization

    /// Initialize with production dependencies
    public convenience init(capacitorBridge: CapacitorBridge? = nil) {
        do {
            let deps = try CapacitorMeteorWebAppDependencies.production(capacitorBridge: capacitorBridge)
            self.init(dependencies: deps)
        } catch {
            // Fallback with minimal dependencies - this will likely fail, but allows compilation
            let tempDeps = CapacitorMeteorWebAppDependencies.test(
                capacitorBridge: capacitorBridge,
                userDefaultsSuiteName: "fallback",
                wwwDirectoryURL: URL(fileURLWithPath: "/tmp"),
                servingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                versionsDirectoryURL: URL(fileURLWithPath: "/tmp")
            )
            self.init(dependencies: tempDeps)
        }
    }

    /// Initialize with injected dependencies (for testing)
    public init(dependencies: CapacitorMeteorWebAppDependencies) {
        self.dependencies = dependencies
        self.configuration = dependencies.configuration

        super.init()

        // Initialize asset bundles
        do {
            try initializeAssetBundles()
        } catch {
            logger.error("Failed to initialize asset bundles: \(error.localizedDescription)")
        }

        // Setup startup timer
        setupStartupTimer()
    }

    private func selectCurrentAssetBundle(initialAssetBundle: AssetBundle) {
        // If a last downloaded version has been set and the asset bundle exists,
        // we set it as the current asset bundle
        if let lastDownloadedVersion = configuration.lastDownloadedVersion,
           let downloadedAssetBundle = assetBundleManager.downloadedAssetBundleWithVersion(
            lastDownloadedVersion) {
            logger.info("📦 Using downloaded asset bundle version: \(lastDownloadedVersion)")
            currentAssetBundle = downloadedAssetBundle
            if configuration.lastKnownGoodVersion != lastDownloadedVersion {
                startStartupTimer()
            }
        } else {
            if let lastDownloadedVersion = configuration.lastDownloadedVersion {
                logger.warning(
                    "⚠️ Downloaded version \(lastDownloadedVersion) was configured but bundle not found, falling back to initial bundle"
                )
            }
            logger.info("📦 Using initial asset bundle version: \(initialAssetBundle.version)")
            currentAssetBundle = initialAssetBundle
        }
    }

    private func initializeAssetBundles() throws {
        assetBundleManager = nil

        // The initial asset bundle consists of the assets bundled with the app
        let wwwURL = dependencies.wwwDirectoryURL

        let initialAssetBundle: AssetBundle
        do {
            initialAssetBundle = try AssetBundle(directoryURL: wwwURL)
        } catch {
            throw HotCodePushError.initializationFailed(
                reason: "Could not load initial asset bundle: \(error.localizedDescription)")
        }

        let fileManager = dependencies.fileSystem
        let versionsDirectoryURL = dependencies.versionsDirectoryURL
        let servingDirectoryURL = dependencies.servingDirectoryURL

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

        // Select bundle AFTER validation (configuration.lastDownloadedVersion may have been cleared)
        selectCurrentAssetBundle(initialAssetBundle: initialAssetBundle)

        pendingAssetBundle = nil

        // Organize and serve the current bundle
        setupCurrentBundle()
    }

    private func setupStartupTimer() {
        startupTimer = dependencies.timerProvider.createTimer(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            self?.logger.error("App startup timed out, reverting to last known good version")
            self?.revertToLastKnownGoodVersion()
        }
    }

    private func updateConfigurationWithCurrentBundle() {
        guard let currentBundle = currentAssetBundle else { return }

        configuration.appId = currentBundle.appId
        configuration.rootURL = currentBundle.rootURL
        configuration.cordovaCompatibilityVersion = currentBundle.cordovaCompatibilityVersion
    }

    private func setupCurrentBundle() {
        guard let currentAssetBundle = currentAssetBundle else { return }

        do {
            let bundleServingDirectory = dependencies.servingDirectoryURL.appendingPathComponent(
                currentAssetBundle.version)

            // Remove existing serving directory for this version
            if dependencies.fileSystem.fileExists(atPath: bundleServingDirectory.path) {
                try dependencies.fileSystem.removeItem(at: bundleServingDirectory)
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
        guard let bridge = dependencies.capacitorBridge else {
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
        DispatchQueue.main.async {
            // Don't start the startup timer if the app started up in the background
            #if os(iOS)
            if UIApplication.shared.applicationState == .active {
                self.logger.info("App startup timer started")
                self.startupTimer?.start(withTimeInterval: self.startupTimeoutInterval)
            }
            #else
            self.logger.info("App startup timer started")
            self.startupTimer?.start(withTimeInterval: self.startupTimeoutInterval)
            #endif
        }
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
        logger.info("App startup completed for bundle \(self.currentAssetBundle.version)")
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
            let bundleServingDirectory = dependencies.servingDirectoryURL.appendingPathComponent(
                pendingAssetBundle.version)

            // Remove existing serving directory for this version
            if dependencies.fileSystem.fileExists(atPath: bundleServingDirectory.path) {
                try dependencies.fileSystem.removeItem(at: bundleServingDirectory)
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
        guard let bridge = dependencies.capacitorBridge else {
            logger.error("Could not get Capacitor bridge for reload")
            return
        }

        DispatchQueue.main.async {
            bridge.reload()
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
            lastKnownGoodVersion) {
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
        guard let bridge = dependencies.capacitorBridge else {
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
            || pendingAssetBundle?.version == manifest.version {
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
        // Notify the Capacitor plugin bridge about update availability
        NotificationCenter.default.post(
            name: .meteorWebappUpdateAvailable,
            object: nil,
            userInfo: ["version": version]
        )
    }

    private func notifyUpdateFailed(error: Error) {
        // Notify the Capacitor plugin bridge about update failure
        NotificationCenter.default.post(
            name: .meteorWebappUpdateFailed,
            object: nil,
            userInfo: ["error": error.localizedDescription]
        )
    }

    // MARK: - Internal Test Methods
    // These methods are only used for testing with @testable import

    /// Get the current asset bundle (test only)
    internal func getCurrentAssetBundle() -> AssetBundle? {
        return currentAssetBundle
    }

    /// Set a pending asset bundle for testing
    internal func setPendingAssetBundle(_ bundle: AssetBundle) {
        pendingAssetBundle = bundle
    }

    /// Perform reload synchronously for testing (wraps the async reload method)
    internal func performReload() throws {
        // Use RunLoop to avoid deadlock instead of semaphore
        var reloadError: Error?
        var completed = false

        reload { error in
            reloadError = error
            completed = true
        }

        // Process run loop until completion, but avoid blocking main thread indefinitely
        let runLoop = RunLoop.current
        let timeout = Date().addingTimeInterval(10.0) // 10 second timeout
        
        while !completed && Date() < timeout {
            runLoop.run(until: Date().addingTimeInterval(0.01))
        }
        
        if !completed {
            throw HotCodePushError.timeoutError(reason: "Reload operation timed out")
        }

        if let error = reloadError {
            throw error
        }
    }

    /// Check for updates with callback (test-compatible interface)
    internal func checkForUpdate(completion: @escaping (UpdateResult) -> Void) {
        checkForUpdates { error in
            if let error = error {
                completion(.error(error))
            } else if self.isUpdateAvailable() {
                completion(.newVersionReady(version: self.pendingAssetBundle?.version ?? "unknown"))
            } else {
                completion(.noUpdate)
            }
        }
    }

    /// Simulate startup completion for testing
    internal func onStartupComplete() {
        // Stop the startup timer and mark version as good if we switched to a new version
        startupTimer?.stop()
        
        if switchedToNewVersion {
            configuration.lastKnownGoodVersion = currentAssetBundle.version
            switchedToNewVersion = false
        }
        
        // Cleanup old versions could be implemented here if needed
        // For now, we'll skip the cleanup in tests
    }

    /// Get the startup timer for testing
    internal var testStartupTimer: TimerInterface? {
        return startupTimer
    }

    /// Start the startup timer for testing (wraps private method)
    internal func testStartStartupTimer() {
        startStartupTimer()
    }
}

// MARK: - Update Result for Tests

internal enum UpdateResult {
    case newVersionReady(version: String)
    case noUpdate
    case error(Error)
}
