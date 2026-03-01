import XCTest

@testable import CapacitorMeteorWebAppPlugin

final class AssetManifestTests: XCTestCase {

    private func manifestData(_ json: String) -> Data {
        return json.data(using: .utf8)!
    }

    // MARK: - Parsing

    func testParsesClientEntriesOnly() throws {
        let json = """
        {
            "version": "v1",
            "cordovaCompatibilityVersions": {"ios": "ios-1"},
            "manifest": [
                {"where": "client", "path": "app.js", "url": "/app.js", "type": "js", "cacheable": true, "hash": "abc123"},
                {"where": "internal", "path": "packages.js", "url": "/packages.js", "type": "js", "cacheable": true, "hash": "def456"},
                {"where": "server", "path": "server.js", "url": "/server.js", "type": "js", "cacheable": true, "hash": "ghi789"},
                {"where": "client", "path": "style.css", "url": "/style.css", "type": "css", "cacheable": true, "hash": "jkl012"}
            ]
        }
        """
        let manifest = try AssetManifest(data: manifestData(json))

        // Only "client" entries should be parsed
        XCTAssertEqual(manifest.entries.count, 2)
        XCTAssertEqual(manifest.entries[0].filePath, "app.js")
        XCTAssertEqual(manifest.entries[1].filePath, "style.css")
    }

    func testThrowsOnMissingVersion() {
        let json = """
        {
            "cordovaCompatibilityVersions": {"ios": "ios-1"},
            "manifest": []
        }
        """
        XCTAssertThrowsError(try AssetManifest(data: manifestData(json))) { error in
            XCTAssertTrue(String(describing: error).contains("version"),
                "Error should mention 'version': \(error)")
        }
    }

    func testThrowsOnMissingCordovaCompatibilityVersion() {
        let json = """
        {
            "version": "v1",
            "cordovaCompatibilityVersions": {"android": "android-1"},
            "manifest": []
        }
        """
        XCTAssertThrowsError(try AssetManifest(data: manifestData(json))) { error in
            XCTAssertTrue(String(describing: error).contains("cordovaCompatibilityVersion"),
                "Error should mention 'cordovaCompatibilityVersion': \(error)")
        }
    }

    func testParsesHashAndSourceMapFields() throws {
        let json = """
        {
            "version": "v1",
            "cordovaCompatibilityVersions": {"ios": "ios-1"},
            "manifest": [
                {
                    "where": "client",
                    "path": "app.js",
                    "url": "/app.js",
                    "type": "js",
                    "cacheable": true,
                    "hash": "abc123def456",
                    "sourceMap": "app.js.map",
                    "sourceMapUrl": "/app.js.map"
                }
            ]
        }
        """
        let manifest = try AssetManifest(data: manifestData(json))

        XCTAssertEqual(manifest.entries.count, 1)
        let entry = manifest.entries[0]
        XCTAssertEqual(entry.hash, "abc123def456")
        XCTAssertEqual(entry.sourceMapPath, "app.js.map")
        XCTAssertEqual(entry.sourceMapURLPath, "/app.js.map")
    }

    func testParsesOptionalFieldsAsNil() throws {
        let json = """
        {
            "version": "v1",
            "cordovaCompatibilityVersions": {"ios": "ios-1"},
            "manifest": [
                {
                    "where": "client",
                    "path": "app.js",
                    "url": "/app.js",
                    "type": "js",
                    "cacheable": true,
                    "hash": "abc123"
                }
            ]
        }
        """
        let manifest = try AssetManifest(data: manifestData(json))

        XCTAssertEqual(manifest.entries.count, 1)
        let entry = manifest.entries[0]
        XCTAssertEqual(entry.hash, "abc123")
        XCTAssertNil(entry.sourceMapPath)
        XCTAssertNil(entry.sourceMapURLPath)
    }
}
