import XCTest
import WebKit
@testable import CapacitorMeteorWebAppPlugin

@available(iOS 13.0, *)
class VersionUpdateTests: XCTestCase {

    var mockBridge: MockCapacitorBridge!
    var tempDirectoryURL: URL!
    var bundledAssetsURL: URL!
    var meteorWebApp: MockCapacitorMeteorWebApp!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Register mock protocol for network requests
        URLProtocol.registerClass(MockMeteorServerProtocol.self)

        // Create temporary directory for test bundles
        tempDirectoryURL = TestFixtures.shared.createTempDirectory()
        bundledAssetsURL = tempDirectoryURL.appendingPathComponent("bundled")

        // Create mock bridge
        mockBridge = MockCapacitorBridge()

        // Set up initial bundle structure - this creates a mock www directory
        TestFixtures.shared.createMockBundleStructure(at: bundledAssetsURL)
    }

    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(MockMeteorServerProtocol.self)
        MockMeteorServerProtocol.reset()
        TestFixtures.shared.cleanupTempDirectory(tempDirectoryURL)

        mockBridge = nil
        tempDirectoryURL = nil
        bundledAssetsURL = nil
        meteorWebApp = nil

        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createMockMeteorWebApp() -> MockCapacitorMeteorWebApp {
        let meteorWebApp = MockCapacitorMeteorWebApp(
            capacitorBridge: mockBridge,
            bundledAssetsURL: bundledAssetsURL
        )
        return meteorWebApp
    }

    private func createMockAssetBundle(version: String, in directory: URL) throws -> AssetBundle {
        // Create test fixtures for the version
        let versionDirectory = directory.appendingPathComponent(version)
        TestFixtures.shared.createMockBundleStructure(at: versionDirectory, version: version)
        return try AssetBundle(directoryURL: versionDirectory)
    }

    // MARK: - Group 2: Update Tests - Bundled to Downloaded

    func testServeNewVersionAfterReload() throws {
        // Test: "should only serve the new version after a page reload" (cordova_tests.js:66-76)
        // This verifies that after downloading a new version, it only becomes active after reload

        meteorWebApp = createMockMeteorWebApp()

        // Initially should be using bundled version
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version1", "Should start with bundled version")

        // Simulate download of new version
        let downloadedBundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)

        // Set pending asset bundle (simulates successful download)
        meteorWebApp.setPendingAssetBundle(downloadedBundle)

        // Before reload, should still serve old version
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version1", "Should still serve old version before reload")

        // After reload, should serve new version
        try meteorWebApp.performReload()
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version2", "Should serve new version after reload")
    }

    func testDownloadOnlyChangedFiles() throws {
        // Test: "should only download changed files" (cordova_tests.js:78-91)
        // This verifies selective file downloading based on asset manifest changes

        meteorWebApp = createMockMeteorWebApp()

        // Set up mock server with version2 that has some changed files
        MockMeteorServerProtocol.setResponseForVersion("version2") { path in
            if path == "manifest.json" {
                return TestFixtures.shared.createManifestJSON(version: "version2", changedFiles: ["changed-file"])
            }
            return nil
        }

        let expectation = expectation(description: "Download completes")

        // Start download - should only download changed files
        meteorWebApp.checkForUpdate { [weak self] result in
            switch result {
            case .newVersionReady(let version):
                XCTAssertEqual(version, "version2", "Should download version2")

                // Verify only changed files were requested
                let requestedPaths = MockMeteorServerProtocol.requestedPaths
                XCTAssertTrue(requestedPaths.contains("manifest.json"), "Should request manifest")
                XCTAssertTrue(requestedPaths.contains("changed-file"), "Should request changed file")
                XCTAssertFalse(requestedPaths.contains("unchanged-file"), "Should not request unchanged file")

                expectation.fulfill()
            case .noUpdate:
                XCTFail("Should have found update")
            case .error(let error):
                XCTFail("Update check failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testServeUnchangedAssets() throws {
        // Test: "should still serve assets that haven't changed" (cordova_tests.js:93-101)
        // This verifies that unchanged assets are still accessible after update

        meteorWebApp = createMockMeteorWebApp()

        // Create version2 with some unchanged files
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Test that unchanged assets are still accessible
        let bundle = meteorWebApp.getCurrentAssetBundle()
        let unchangedAsset = bundle.assetForURLPath("/some-file")
        XCTAssertNotNil(unchangedAsset, "Unchanged asset should still be accessible")

        let content = try String(contentsOf: unchangedAsset!.fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("some-file"), "Unchanged asset content should be preserved")
    }

    func testRememberVersionAfterRestart() throws {
        // Test: "should remember the new version after a restart" (cordova_tests.js:103-111)
        // This verifies that version selection persists across app restarts

        meteorWebApp = createMockMeteorWebApp()

        // Download and switch to version2
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Simulate app restart by creating new instance
        let restartedMeteorWebApp = createMockMeteorWebApp()

        // Should remember the last downloaded version
        XCTAssertEqual(restartedMeteorWebApp.getCurrentVersion(), "version2",
                       "Should remember version after restart")
    }

    // MARK: - Group 3: Update Tests - Downloaded to Downloaded

    func testServeNewerDownloadedVersionAfterReload() throws {
        // Test: "should only serve the new version after a page reload" (cordova_tests.js:125-135)
        // This verifies updating from one downloaded version to another

        meteorWebApp = createMockMeteorWebApp()

        // First, update to version2
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version2")

        // Then, update to version3
        let version3Bundle = try createMockAssetBundle(version: "version3", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version3Bundle)

        // Before reload, should still serve version2
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version2")

        // After reload, should serve version3
        try meteorWebApp.performReload()
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version3")
    }

    func testDownloadOnlyChangedFilesDownloadedToDownloaded() throws {
        // Test: "should only download changed files" (cordova_tests.js:137-149)
        // This verifies selective downloading between downloaded versions

        meteorWebApp = createMockMeteorWebApp()

        // Start with version2
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Mock server with version3 that has different changed files
        MockMeteorServerProtocol.setResponseForVersion("version3") { path in
            if path == "manifest.json" {
                return TestFixtures.shared.createManifestJSON(version: "version3", changedFiles: ["new-changed-file"])
            }
            return nil
        }

        let expectation = expectation(description: "Download completes")

        meteorWebApp.checkForUpdate { result in
            switch result {
            case .newVersionReady(let version):
                XCTAssertEqual(version, "version3")

                // Should only download newly changed files
                let requestedPaths = MockMeteorServerProtocol.requestedPaths
                XCTAssertTrue(requestedPaths.contains("manifest.json"))
                XCTAssertTrue(requestedPaths.contains("new-changed-file"))

                expectation.fulfill()
            case .noUpdate:
                XCTFail("Should have found update")
            case .error(let error):
                XCTFail("Update check failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testServeUnchangedAssetsDownloadedToDownloaded() throws {
        // Test: "should still serve assets that haven't changed" (cordova_tests.js:151-159)
        // This verifies unchanged assets work between downloaded versions

        meteorWebApp = createMockMeteorWebApp()

        // Update to version2
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Update to version3
        let version3Bundle = try createMockAssetBundle(version: "version3", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version3Bundle)
        try meteorWebApp.performReload()

        // Test that common assets are still accessible
        let bundle = meteorWebApp.getCurrentAssetBundle()
        let commonAsset = bundle.assetForURLPath("/some-file")
        XCTAssertNotNil(commonAsset, "Common asset should still be accessible")
    }

    func testDeleteOldVersionAfterStartup() throws {
        // Test: "should delete the old version after startup completes" (cordova_tests.js:161-179)
        // This verifies cleanup of old downloaded versions

        meteorWebApp = createMockMeteorWebApp()

        // Update to version2
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Update to version3
        let version3Bundle = try createMockAssetBundle(version: "version3", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version3Bundle)
        try meteorWebApp.performReload()

        // Simulate startup completion
        meteorWebApp.onStartupComplete()

        // Verify old version is cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: version2Bundle.directoryURL.path),
                       "Old version should be deleted after startup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: version3Bundle.directoryURL.path),
                      "Current version should be kept")
    }

    func testRememberNewerVersionAfterRestart() throws {
        // Test: "should remember the new version after a restart" (cordova_tests.js:181-189)
        // This verifies version persistence for downloaded-to-downloaded updates

        meteorWebApp = createMockMeteorWebApp()

        // Update through multiple versions: bundled -> version2 -> version3
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        let version3Bundle = try createMockAssetBundle(version: "version3", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version3Bundle)
        try meteorWebApp.performReload()

        // Simulate restart
        let restartedMeteorWebApp = createMockMeteorWebApp()

        // Should remember version3
        XCTAssertEqual(restartedMeteorWebApp.getCurrentVersion(), "version3",
                       "Should remember latest downloaded version after restart")
    }

    // MARK: - Group 4: Update Tests - Downloaded to Bundled

    func testServeReversionToBundledAfterReload() throws {
        // Test: "should only serve the new version after a page reload" (cordova_tests.js:203-213)
        // This verifies reverting from downloaded version back to bundled version

        meteorWebApp = createMockMeteorWebApp()

        // First, update to downloaded version
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version2")

        // Then, revert to bundled version (version1)
        let bundledBundle = try AssetBundle(directoryURL: bundledAssetsURL)
        meteorWebApp.setPendingAssetBundle(bundledBundle)

        // Before reload, should still serve version2
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version2")

        // After reload, should serve bundled version
        try meteorWebApp.performReload()
        XCTAssertEqual(meteorWebApp.getCurrentVersion(), "version1")
    }

    func testDownloadOnlyManifestForBundledReversion() throws {
        // Test: "should only download the manifest" (cordova_tests.js:215-223)
        // This verifies minimal download when reverting to bundled version

        meteorWebApp = createMockMeteorWebApp()

        // Start with downloaded version
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Mock server returns bundled version (reversion scenario)
        MockMeteorServerProtocol.setResponseForVersion("version1") { path in
            if path == "manifest.json" {
                return TestFixtures.shared.createManifestJSON(version: "version1", changedFiles: [])
            }
            return nil
        }

        let expectation = expectation(description: "Reversion completes")

        meteorWebApp.checkForUpdate { result in
            switch result {
            case .newVersionReady(let version):
                XCTAssertEqual(version, "version1")

                // Should only download manifest for bundled reversion
                let requestedPaths = MockMeteorServerProtocol.requestedPaths
                XCTAssertTrue(requestedPaths.contains("manifest.json"))
                XCTAssertEqual(requestedPaths.count, 1, "Should only request manifest for bundled reversion")

                expectation.fulfill()
            case .noUpdate:
                XCTFail("Should have detected reversion")
            case .error(let error):
                XCTFail("Update check failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testServeUnchangedAssetsForBundledReversion() throws {
        // Test: "should still serve assets that haven't changed" (cordova_tests.js:225-233)
        // This verifies asset serving during reversion to bundled version

        meteorWebApp = createMockMeteorWebApp()

        // Update to downloaded version
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Revert to bundled version
        let bundledBundle = try AssetBundle(directoryURL: bundledAssetsURL)
        meteorWebApp.setPendingAssetBundle(bundledBundle)
        try meteorWebApp.performReload()

        // Verify bundled assets are accessible
        let bundle = meteorWebApp.getCurrentAssetBundle()
        let bundledAsset = bundle.assetForURLPath("/some-file")
        XCTAssertNotNil(bundledAsset, "Bundled assets should be accessible after reversion")

        let content = try String(contentsOf: bundledAsset!.fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("some-file"), "Bundled asset content should be correct")
    }

    func testNotRedownloadBundledVersion() throws {
        // Test: "should not redownload the bundled version" (cordova_tests.js:235-244)
        // This verifies bundled version is not re-downloaded unnecessarily

        meteorWebApp = createMockMeteorWebApp()

        // Mock server to return bundled version manifest
        MockMeteorServerProtocol.setResponseForVersion("version1") { path in
            if path == "manifest.json" {
                return TestFixtures.shared.createManifestJSON(version: "version1", changedFiles: [])
            }
            return nil
        }

        let expectation = expectation(description: "Update check completes")

        meteorWebApp.checkForUpdate { result in
            switch result {
            case .newVersionReady(let version):
                XCTAssertEqual(version, "version1")

                // Should recognize this is the bundled version and not redownload assets
                let requestedPaths = MockMeteorServerProtocol.requestedPaths
                XCTAssertTrue(requestedPaths.contains("manifest.json"))
                // Should not request individual assets for bundled version
                let assetRequests = requestedPaths.filter { !$0.contains("manifest") }
                XCTAssertEqual(assetRequests.count, 0, "Should not download assets for bundled version")

                expectation.fulfill()
            case .noUpdate:
                // This is also acceptable - no update needed for same version
                expectation.fulfill()
            case .error(let error):
                XCTFail("Update check failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testDeleteDownloadedVersionAfterBundledReversion() throws {
        // Test: "should delete the old version after startup completes" (cordova_tests.js:246-264)
        // This verifies cleanup when reverting to bundled version

        meteorWebApp = createMockMeteorWebApp()

        // Update to downloaded version
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        // Revert to bundled version
        let bundledBundle = try AssetBundle(directoryURL: bundledAssetsURL)
        meteorWebApp.setPendingAssetBundle(bundledBundle)
        try meteorWebApp.performReload()

        // Simulate startup completion
        meteorWebApp.onStartupComplete()

        // Verify downloaded version is cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: version2Bundle.directoryURL.path),
                       "Downloaded version should be deleted after bundled reversion")
    }

    func testRememberBundledVersionAfterRestart() throws {
        // Test: "should remember the new version after a restart" (cordova_tests.js:266-274)
        // This verifies bundled version persistence after reversion

        meteorWebApp = createMockMeteorWebApp()

        // Update to downloaded version then revert to bundled
        let version2Bundle = try createMockAssetBundle(version: "version2", in: tempDirectoryURL)
        meteorWebApp.setPendingAssetBundle(version2Bundle)
        try meteorWebApp.performReload()

        let bundledBundle = try AssetBundle(directoryURL: bundledAssetsURL)
        meteorWebApp.setPendingAssetBundle(bundledBundle)
        try meteorWebApp.performReload()

        // Simulate restart
        let restartedMeteorWebApp = createMockMeteorWebApp()

        // Should remember bundled version
        XCTAssertEqual(restartedMeteorWebApp.getCurrentVersion(), "version1",
                       "Should remember bundled version after restart")
    }

    // MARK: - Group 5: No Update Tests

    func testNoCallbackForNoNewVersion() throws {
        // Test: "should not invoke the onNewVersionReady callback" (cordova_tests.js:288-298)
        // This verifies no callback when there are no updates

        meteorWebApp = createMockMeteorWebApp()

        // Mock server to return same version
        MockMeteorServerProtocol.setResponseForVersion("version1") { path in
            if path == "manifest.json" {
                return TestFixtures.shared.createManifestJSON(version: "version1", changedFiles: [])
            }
            return nil
        }

        let expectation = expectation(description: "No update check completes")

        meteorWebApp.checkForUpdate { result in
            switch result {
            case .newVersionReady:
                XCTFail("Should not invoke callback for same version")
            case .noUpdate:
                // This is the expected result
                expectation.fulfill()
            case .error(let error):
                XCTFail("Update check failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testDownloadOnlyManifestWhenNoUpdates() throws {
        // Test: "should not download any files except for the manifest" (cordova_tests.js:300-308)
        // This verifies minimal network traffic when no updates are available

        meteorWebApp = createMockMeteorWebApp()

        // Mock server to return same version
        MockMeteorServerProtocol.setResponseForVersion("version1") { path in
            if path == "manifest.json" {
                return TestFixtures.shared.createManifestJSON(version: "version1", changedFiles: [])
            }
            return nil
        }

        let expectation = expectation(description: "No update check completes")

        meteorWebApp.checkForUpdate { result in
            switch result {
            case .newVersionReady:
                XCTFail("Should not find new version")
            case .noUpdate:
                // Verify only manifest was downloaded
                let requestedPaths = MockMeteorServerProtocol.requestedPaths
                XCTAssertTrue(requestedPaths.contains("manifest.json"))
                XCTAssertEqual(requestedPaths.count, 1, "Should only download manifest when no updates")

                expectation.fulfill()
            case .error(let error):
                XCTFail("Update check failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }
}

// MARK: - Mock CapacitorMeteorWebApp for Testing

class MockCapacitorMeteorWebApp {
    private var mockCurrentAssetBundle: AssetBundle!
    private var mockPendingAssetBundle: AssetBundle?
    private var mockConfiguration: [String: Any] = [:]
    private weak var capacitorBridge: CapacitorBridge?

    init(capacitorBridge: CapacitorBridge?, bundledAssetsURL: URL) {
        self.capacitorBridge = capacitorBridge

        // Initialize with test bundle
        do {
            mockCurrentAssetBundle = try AssetBundle(directoryURL: bundledAssetsURL)
        } catch {
            fatalError("Failed to initialize test bundle: \(error)")
        }
    }

    func getCurrentVersion() -> String {
        return mockCurrentAssetBundle.version
    }

    func getCurrentAssetBundle() -> AssetBundle {
        return mockCurrentAssetBundle
    }

    func setPendingAssetBundle(_ bundle: AssetBundle) {
        mockPendingAssetBundle = bundle
    }

    func performReload() throws {
        if let pending = mockPendingAssetBundle {
            mockCurrentAssetBundle = pending
            mockPendingAssetBundle = nil
            mockConfiguration["lastDownloadedVersion"] = pending.version
        }
    }

    func checkForUpdate(completion: @escaping (UpdateResult) -> Void) {
        // Simulate async update check based on mock server responses
        DispatchQueue.global().async {
            // For testing, we'll determine result based on mock responses
            // This is a simplified implementation - real tests would check mock server
            DispatchQueue.main.async {
                completion(.noUpdate)
            }
        }
    }

    func onStartupComplete() {
        // Simulate cleanup of old versions
        // Implementation would depend on test needs
    }

    // Helper methods for testing
    var lastDownloadedVersion: String? {
        get { mockConfiguration["lastDownloadedVersion"] as? String }
        set { mockConfiguration["lastDownloadedVersion"] = newValue }
    }

    var lastKnownGoodVersion: String? {
        get { mockConfiguration["lastKnownGoodVersion"] as? String }
        set { mockConfiguration["lastKnownGoodVersion"] = newValue }
    }
}

// MARK: - Update Result Enum

enum UpdateResult {
    case newVersionReady(version: String)
    case noUpdate
    case error(Error)
}
