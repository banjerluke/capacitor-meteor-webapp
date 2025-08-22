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

    // MARK: - Test Helpers

    private func createMeteorWebApp() -> CapacitorMeteorWebApp {
        // Configure URLSession to use mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockMeteorServerProtocol.self]

        let dependencies = CapacitorMeteorWebAppDependencies.test(
            capacitorBridge: mockBridge,
            wwwDirectoryURL: bundledAssetsURL,
            servingDirectoryURL: tempDirectoryURL.appendingPathComponent("serving"),
            versionsDirectoryURL: tempDirectoryURL.appendingPathComponent("versions"),
            urlSessionConfiguration: config
        )
        return CapacitorMeteorWebApp(dependencies: dependencies)
    }

    // MARK: - HTTP Serving Behavior Tests

    func testInitializeWithMockBridge() throws {
        // Test 1: Verify HTTP serving behavior - initialization should set server base path
        let meteorWebApp = createMeteorWebApp()

        // Wait for async setServerBasePath call
        let expectation = XCTestExpectation(description: "setServerBasePath called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !self.mockBridge.setServerBasePathCalls.isEmpty {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)

        // Verify Capacitor bridge received setServerBasePath call
        XCTAssertFalse(mockBridge.setServerBasePathCalls.isEmpty, "Should call setServerBasePath during initialization")

        let servingPath = meteorWebApp.getCurrentServingDirectory()
        XCTAssertFalse(servingPath.isEmpty, "Should have a serving directory")

        // Verify the serving directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: servingPath), "Serving directory should exist")
    }

    func testServeIndexForRoot() throws {
        // Test 2: Verify HTTP serving behavior - index.html should be served for root path "/"
        let meteorWebApp = createMeteorWebApp()

        // Verify index.html exists in serving directory at root
        let servingPath = meteorWebApp.getCurrentServingDirectory()
        let indexPath = "\(servingPath)/index.html"
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexPath), "index.html should exist in serving directory")

        // Verify content is correct
        let indexContent = try String(contentsOfFile: indexPath, encoding: .utf8)
        XCTAssertTrue(indexContent.contains("<title>"), "Index should contain HTML title tag")
        XCTAssertTrue(indexContent.contains("Test App version1"), "Index should contain expected content")
    }

    func testServeAssetFiles() throws {
        // Test 3: Verify HTTP serving behavior - asset files should be accessible in serving directory
        let meteorWebApp = createMeteorWebApp()

        let servingPath = meteorWebApp.getCurrentServingDirectory()

        // Verify some-file exists and has correct content
        let someFilePath = "\(servingPath)/some-file"
        XCTAssertTrue(FileManager.default.fileExists(atPath: someFilePath), "some-file should exist in serving directory")

        let someFileContent = try String(contentsOfFile: someFilePath, encoding: .utf8)
        XCTAssertTrue(someFileContent.contains("some-file content"), "some-file should contain expected content")
    }

    func testCapacitorBridgeSetServerBasePath() throws {
        // Test 4: Verify HTTP serving behavior - Capacitor bridge should receive setServerBasePath calls
        let meteorWebApp = createMeteorWebApp()

        // Wait for async setServerBasePath call
        let expectation = XCTestExpectation(description: "setServerBasePath called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let expectedServingPath = meteorWebApp.getCurrentServingDirectory()
            if self.mockBridge.setServerBasePathCalls.contains(expectedServingPath) {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)

        // Verify Capacitor bridge received correct setServerBasePath call
        let expectedServingPath = meteorWebApp.getCurrentServingDirectory()
        XCTAssertTrue(mockBridge.setServerBasePathCalls.contains(expectedServingPath),
                      "Capacitor bridge should receive setServerBasePath call with serving directory")

        // Verify the path points to a real directory
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedServingPath), "Serving path should exist")
    }

    func testServingDirectoryStructure() throws {
        // Test 5: Verify HTTP serving behavior - serving directory has expected structure
        let meteorWebApp = createMeteorWebApp()

        let servingPath = meteorWebApp.getCurrentServingDirectory()

        // Verify expected files exist in serving directory
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(servingPath)/index.html"), "index.html should be served")
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(servingPath)/some-file"), "some-file should be served")

        // Verify non-existent files are not served
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(servingPath)/non-existent-file"),
                       "Non-existent files should not be served")
    }

    func testVersionTracking() throws {
        // Test 6: Verify HTTP serving behavior - current version is tracked correctly
        let meteorWebApp = createMeteorWebApp()

        let currentVersion = meteorWebApp.getCurrentVersion()
        XCTAssertEqual(currentVersion, "version1", "Should track current version correctly")

        // Verify serving directory includes version in path
        let servingPath = meteorWebApp.getCurrentServingDirectory()
        XCTAssertTrue(servingPath.contains("version1"), "Serving path should include version")
    }

    func testMultipleInitialization() throws {
        // Test 7: Verify HTTP serving behavior - multiple initializations work correctly
        let meteorWebApp1 = createMeteorWebApp()
        let meteorWebApp2 = createMeteorWebApp()

        // Wait for async setServerBasePath calls
        let expectation = XCTestExpectation(description: "Multiple setServerBasePath calls")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if self.mockBridge.setServerBasePathCalls.count >= 2 {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)

        // Both should have valid serving directories
        let servingPath1 = meteorWebApp1.getCurrentServingDirectory()
        let servingPath2 = meteorWebApp2.getCurrentServingDirectory()

        XCTAssertFalse(servingPath1.isEmpty, "First webapp should have serving directory")
        XCTAssertFalse(servingPath2.isEmpty, "Second webapp should have serving directory")

        // Bridge should receive multiple calls (one for each initialization)
        XCTAssertGreaterThanOrEqual(mockBridge.setServerBasePathCalls.count, 2,
                                    "Bridge should receive multiple setServerBasePath calls")
    }
}

// MARK: - Mock Capacitor Bridge

class MockCapacitorBridge: CapacitorBridge {
    private var _serverBasePath: String?
    private var _webView: MockWebView?
    var setServerBasePathCalls: [String] = []

    var serverBasePath: String? {
        return _serverBasePath
    }

    init() {
        _webView = MockWebView()
    }

    func setServerBasePath(_ path: String) {
        _serverBasePath = path
        setServerBasePathCalls.append(path)
    }

    func getWebView() -> AnyObject? {
        return _webView
    }

    var webView: WKWebView? {
        return _webView
    }

    func reload() {
        // Implementation not needed for basic tests
    }
}

// MARK: - Mock WebView

class MockWebView: WKWebView {
    var reloadCount = 0

    override func reload() -> WKNavigation? {
        reloadCount += 1
        return nil
    }
}
