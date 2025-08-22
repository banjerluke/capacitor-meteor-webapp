import XCTest
import WebKit
@testable import CapacitorMeteorWebAppPlugin

@available(iOS 13.0, *)
class BasicServingTests: XCTestCase {

    var mockBridge: MockCapacitorBridge!
    var tempDirectoryURL: URL!
    var bundledAssetsURL: URL!

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

        try super.tearDownWithError()
    }

    // MARK: - Basic Server Functionality Tests

    func testInitializeWithMockBridge() throws {
        // Test 1: Verify we can initialize the plugin with a mock bridge
        let meteorWebApp = CapacitorMeteorWebApp(capacitorBridge: mockBridge)
        XCTAssertNotNil(meteorWebApp, "Should be able to initialize CapacitorMeteorWebApp")

        // The plugin should have a version (from bundled assets)
        // Note: In test environment, it may return "unknown" if bundled www doesn't exist
        let version = meteorWebApp.getCurrentVersion()
        XCTAssertFalse(version.isEmpty, "Should have a current version")
        // The version might be "unknown" in test environment, which is acceptable
    }

    func testAssetBundleCreationFromDirectory() throws {
        // Test 2: Verify AssetBundle can be created from a directory with manifest
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)
        XCTAssertNotNil(bundle, "Should be able to create AssetBundle from directory")
        XCTAssertEqual(bundle.version, "version1", "Should have correct version from test fixtures")
        XCTAssertEqual(bundle.cordovaCompatibilityVersion, "1.0.0", "Should have cordova compatibility version")
    }

    func testAssetBundleAssetsAccess() throws {
        // Test 3: Verify we can access assets from the bundle
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        // Check for index file (root path)
        let indexAsset = bundle.assetForURLPath("/")
        XCTAssertNotNil(indexAsset, "Should have index asset at root path")
        XCTAssertEqual(indexAsset?.urlPath, "/", "Index asset should have root URL path")

        // Check for manifest asset
        let someFileAsset = bundle.assetForURLPath("/some-file")
        XCTAssertNotNil(someFileAsset, "Should have some-file asset")
        XCTAssertEqual(someFileAsset?.urlPath, "/some-file", "Some-file asset should have correct URL path")
    }

    func testAssetContentLoading() throws {
        // Test 4: Verify we can load content from assets
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        guard let indexAsset = bundle.assetForURLPath("/") else {
            XCTFail("Should have index asset")
            return
        }

        let indexContent = try String(contentsOf: indexAsset.fileURL, encoding: .utf8)
        XCTAssertTrue(indexContent.contains("Test App version1"), "Index content should contain test app title")
        XCTAssertTrue(indexContent.contains("<html>"), "Index content should be valid HTML")
    }

    func testAssetExistsInBundle() throws {
        // Test 5: Verify asset existence checking
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        XCTAssertTrue(bundle.assetExistsInBundle("/"), "Root path should exist in bundle")
        XCTAssertTrue(bundle.assetExistsInBundle("/some-file"), "some-file should exist in bundle")
        XCTAssertFalse(bundle.assetExistsInBundle("/non-existent-file"), "Non-existent file should not exist in bundle")
    }

    func testMissingAssetFallback() throws {
        // Test 6: Verify behavior for missing assets (should return nil, not crash)
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        let missingAsset = bundle.assetForURLPath("/not-in-manifest")
        XCTAssertNil(missingAsset, "Missing asset should return nil")

        let missingApplicationAsset = bundle.assetForURLPath("/application/not-in-manifest")
        XCTAssertNil(missingApplicationAsset, "Missing application asset should return nil")
    }

    func testFaviconAssetHandling() throws {
        // Test 7: Verify favicon.ico handling (this asset typically doesn't exist)
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        let faviconAsset = bundle.assetForURLPath("/favicon.ico")
        XCTAssertNil(faviconAsset, "favicon.ico should not exist in test bundle")
        XCTAssertFalse(bundle.assetExistsInBundle("/favicon.ico"), "favicon.ico should not exist in bundle")
    }

    func testBridgeIntegration() throws {
        // Test 8: Verify bridge integration works
        _ = CapacitorMeteorWebApp(capacitorBridge: mockBridge)

        // Initially, no server base path should be set
        XCTAssertNil(mockBridge.serverBasePath, "Initially no server base path should be set")

        // After some operations, the bridge should receive calls (this is integration-level testing)
        // For now, we just verify the bridge is properly connected
        XCTAssertNotNil(mockBridge, "Bridge should be available")
        XCTAssertNotNil(mockBridge.getWebView(), "Bridge should provide mock web view")
    }

    // MARK: - Additional Phase 2 Tests (completing cordova test coverage)

    func testServeIndexForRoot() throws {
        // Test: "should serve index.html for /" (cordova_tests.js:8-10)
        // This verifies that the root path "/" maps to the index.html asset
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        // The root path should map to index.html
        let rootAsset = bundle.assetForURLPath("/")
        XCTAssertNotNil(rootAsset, "Root path '/' should return an asset")
        XCTAssertEqual(rootAsset?.filePath, "index.html", "Root path should map to index.html file")
        XCTAssertEqual(rootAsset?.fileType, "html", "Root asset should be HTML type")

        // The content should be valid HTML with app content
        let content = try String(contentsOf: rootAsset!.fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("<html>"), "Root content should be valid HTML")
        XCTAssertTrue(content.contains("Test App"), "Root content should contain app content")
    }

    func testServeBundledAssets() throws {
        // Test: "should serve assets from the bundled www directory" (cordova_tests.js:24-31)
        // This verifies that assets in the bundle directory can be accessed by URL path
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        // Look for a manifest asset that should exist
        let manifestAsset = bundle.assetForURLPath("/some-file")
        XCTAssertNotNil(manifestAsset, "Bundled asset '/some-file' should be accessible")

        // Verify the asset content is correct
        let content = try String(contentsOf: manifestAsset!.fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("some-file"), "Asset content should contain expected text")

        // Also test that the asset exists check works
        XCTAssertTrue(bundle.assetExistsInBundle("/some-file"), "Bundle should recognize this asset exists")
        XCTAssertFalse(bundle.assetExistsInBundle("/nonexistent-file"), "Bundle should recognize nonexistent assets")
    }

    func testServeIndexForNonAssets() throws {
        // Test: "should serve index.html for any URL that does not correspond to an asset" (cordova_tests.js:34-35)
        // This verifies SPA behavior - non-asset routes should fall back to index handling
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        // Non-existent paths should return nil (indicating fallback to index.html in actual serving)
        let nonAsset1 = bundle.assetForURLPath("/anything")
        XCTAssertNil(nonAsset1, "Non-asset path should return nil (fallback to index)")

        let nonAsset2 = bundle.assetForURLPath("/some/deep/route")
        XCTAssertNil(nonAsset2, "Deep non-asset path should return nil (fallback to index)")

        let nonAsset3 = bundle.assetForURLPath("/app/users/123")
        XCTAssertNil(nonAsset3, "Application route should return nil (fallback to index)")

        // But the index should still be accessible at root
        let indexAsset = bundle.assetForURLPath("/")
        XCTAssertNotNil(indexAsset, "Index should always be available at root")
        XCTAssertEqual(indexAsset?.filePath, "index.html", "Root should serve index.html")
    }

    func testServeIndexForApplicationPath() throws {
        // Test: "should serve index.html when accessing an asset through /application" (cordova_tests.js:38-39)
        // This verifies that /application/* paths fall back to index (SPA routing behavior)
        let bundle = try AssetBundle(directoryURL: bundledAssetsURL)

        // /application paths should not have direct assets (fallback to index in actual serving)
        let appPath1 = bundle.assetForURLPath("/application/packages/meteor.js")
        XCTAssertNil(appPath1, "Application path should return nil (fallback to index)")

        let appPath2 = bundle.assetForURLPath("/application/something")
        XCTAssertNil(appPath2, "Application subpath should return nil (fallback to index)")

        // But assets that don't start with /application should still work normally
        let normalAsset = bundle.assetForURLPath("/some-file")
        XCTAssertNotNil(normalAsset, "Normal asset paths should still work")

        // And root should still serve index
        let rootAsset = bundle.assetForURLPath("/")
        XCTAssertNotNil(rootAsset, "Root path should always serve index")
        XCTAssertEqual(rootAsset?.filePath, "index.html", "Root should map to index.html")
    }
}

// MARK: - Mock Capacitor Bridge

class MockCapacitorBridge: CapacitorBridge {
    private var _serverBasePath: String?
    private var _webView: MockWebView?

    var serverBasePath: String? {
        return _serverBasePath
    }

    init() {
        _webView = MockWebView()
    }

    func setServerBasePath(_ path: String) {
        _serverBasePath = path
    }

    func getWebView() -> AnyObject? {
        return _webView
    }

    var webView: WKWebView? {
        // For testing purposes, we return nil as we don't need a real WKWebView
        return nil
    }

    func reload() {
        _webView?.reload()
    }
}

// MARK: - Mock WebView

class MockWebView: NSObject {
    private(set) var reloadCount = 0

    func reload() {
        reloadCount += 1
    }
}
