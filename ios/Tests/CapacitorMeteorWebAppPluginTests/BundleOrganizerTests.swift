import XCTest

@testable import CapacitorMeteorWebAppPlugin

final class BundleOrganizerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleOrganizerTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Tests

    func testOrganizeBundleInjectsShimAndCopiesAssets() throws {
        let builder = TestBundleBuilder(
            version: "v-org", appId: "test-app",
            rootUrl: "http://example.com", compatibility: "ios-1")
            .addAsset("app/main.js", type: "js", content: "console.log('org');")
            .addAsset("app/style.css", type: "css", content: "body{}")

        let bundleDir = tempDir.appendingPathComponent("bundle")
        try builder.writeToDirectory(bundleDir)
        let bundle = try AssetBundle(directoryURL: bundleDir)

        let targetDir = tempDir.appendingPathComponent("organized")
        try BundleOrganizer.organizeBundle(bundle, in: targetDir)

        // index.html should contain the WebAppLocalServer shim
        let indexURL = targetDir.appendingPathComponent("index.html")
        let indexContent = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(indexContent.contains("WebAppLocalServer"),
            "index.html should contain WebAppLocalServer shim")

        // Other assets should exist at their URL-path locations
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: targetDir.appendingPathComponent("app/main.js").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: targetDir.appendingPathComponent("app/style.css").path))
    }

    func testValidateBundleDetectsTraversal() throws {
        let builder = TestBundleBuilder(
            version: "v-trav", appId: "test-app",
            rootUrl: "http://example.com", compatibility: "ios-1")

        let bundleDir = tempDir.appendingPathComponent("bundle")
        try builder.writeToDirectory(bundleDir)
        let bundle = try AssetBundle(directoryURL: bundleDir)

        // Manually inject a malicious asset with ".." in the URL path
        let maliciousAsset = Asset(
            bundle: bundle, filePath: "../../etc/passwd",
            urlPath: "/../../etc/passwd", fileType: "text", cacheable: false)
        bundle.addAsset(maliciousAsset)

        let errors = BundleOrganizer.validateBundleOrganization(bundle)
        XCTAssertFalse(errors.isEmpty, "Should detect path traversal")
        XCTAssertTrue(errors.first?.contains("..") ?? false)
    }

    func testTargetURLMapping() throws {
        let builder = TestBundleBuilder(
            version: "v-url", appId: "test-app",
            rootUrl: "http://example.com", compatibility: "ios-1")

        let bundleDir = tempDir.appendingPathComponent("bundle")
        try builder.writeToDirectory(bundleDir)
        let bundle = try AssetBundle(directoryURL: bundleDir)
        let targetDir = tempDir.appendingPathComponent("target")

        // Leading slash is stripped
        let jsAsset = Asset(
            bundle: bundle, filePath: "app/main.js",
            urlPath: "/app/main.js", fileType: "js", cacheable: true)
        let jsTarget = BundleOrganizer.targetURLForAsset(jsAsset, in: targetDir)
        XCTAssertEqual(jsTarget, targetDir.appendingPathComponent("app/main.js"))

        // Root path "/" maps to "index.html"
        let indexAsset = Asset(
            bundle: bundle, filePath: "index.html",
            urlPath: "/", fileType: "html", cacheable: false)
        let indexTarget = BundleOrganizer.targetURLForAsset(indexAsset, in: targetDir)
        XCTAssertEqual(indexTarget, targetDir.appendingPathComponent("index.html"))
    }

    func testCleanupRemovesDirectory() throws {
        let builder = TestBundleBuilder(
            version: "v-clean", appId: "test-app",
            rootUrl: "http://example.com", compatibility: "ios-1")
            .addAsset("app/main.js", type: "js", content: "cleanup")

        let bundleDir = tempDir.appendingPathComponent("bundle")
        try builder.writeToDirectory(bundleDir)
        let bundle = try AssetBundle(directoryURL: bundleDir)

        let targetDir = tempDir.appendingPathComponent("organized")
        try BundleOrganizer.organizeBundle(bundle, in: targetDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDir.path))

        try BundleOrganizer.cleanupOrganizedBundle(at: targetDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetDir.path))
    }

    func testOrganizeBundleHandlesInheritedAssets() throws {
        let parentBuilder = TestBundleBuilder(
            version: "v-parent", appId: "test-app",
            rootUrl: "http://example.com", compatibility: "ios-1")
            .addAsset("app/shared.js", type: "js", content: "// shared")

        let parentDir = tempDir.appendingPathComponent("parent")
        try parentBuilder.writeToDirectory(parentDir)
        let parentBundle = try AssetBundle(directoryURL: parentDir)

        let childBuilder = TestBundleBuilder(
            version: "v-child", appId: "test-app",
            rootUrl: "http://example.com", compatibility: "ios-1")
            .addAsset("app/child.js", type: "js", content: "// child")

        let childDir = tempDir.appendingPathComponent("child")
        try childBuilder.writeToDirectory(childDir)
        let childBundle = try AssetBundle(directoryURL: childDir, parentAssetBundle: parentBundle)

        let targetDir = tempDir.appendingPathComponent("organized")
        try BundleOrganizer.organizeBundle(childBundle, in: targetDir)

        // Child's own asset
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: targetDir.appendingPathComponent("app/child.js").path))
        // Parent's asset organized alongside
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: targetDir.appendingPathComponent("app/shared.js").path))
    }
}
