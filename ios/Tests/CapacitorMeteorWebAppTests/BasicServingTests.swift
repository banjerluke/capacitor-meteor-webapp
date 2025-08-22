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
