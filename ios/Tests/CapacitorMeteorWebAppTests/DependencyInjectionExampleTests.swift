//
// DependencyInjectionExampleTests.swift
//
// Example tests demonstrating the dependency injection approach for CapacitorMeteorWebApp
//

import XCTest
import WebKit
@testable import CapacitorMeteorWebAppPlugin

@available(iOS 13.0, *)
final class DependencyInjectionExampleTests: XCTestCase {

    // MARK: - Example Tests

    /// Example: Testing CapacitorMeteorWebApp with dependency injection
    func testCapacitorMeteorWebAppWithDependencyInjection() async throws {
        let (dependencies, mocks) = try TestDependencyFactory.createTestDependencies()
        defer { mocks.cleanup() }

        // Create a simple manifest and asset files in the temp www directory
        try createMinimalWwwBundle(at: dependencies.wwwDirectoryURL)

        // Initialize CapacitorMeteorWebApp with injected dependencies
        let webapp = CapacitorMeteorWebApp(dependencies: dependencies)

        // Verify the app initialized correctly
        XCTAssertEqual(webapp.getCurrentVersion(), "test-version-1.0")
        XCTAssertFalse(webapp.isUpdateAvailable())

        // Verify timer was created
        XCTAssertEqual(mocks.timerProvider.createdTimers.count, 1)

        // Verify Capacitor bridge was called to set server path
        XCTAssertTrue(mocks.capacitorBridge.setServerBasePathCalls.count > 0)
        XCTAssertTrue(mocks.capacitorBridge.setServerBasePathCalls.first?.contains("test-version-1.0") == true)
    }

    /// Example: Testing startup timeout behavior
    func testStartupTimeoutWithDependencyInjection() async throws {
        let (dependencies, mocks) = try TestDependencyFactory.createTestDependencies()
        defer { mocks.cleanup() }

        // Create a simple manifest and asset files
        try createMinimalWwwBundle(at: dependencies.wwwDirectoryURL)

        // Initialize webapp
        let _ = CapacitorMeteorWebApp(dependencies: dependencies)

        // Get the created timer
        guard let timer = mocks.timerProvider.createdTimers.first else {
            XCTFail("No timer was created")
            return
        }

        // Verify timer starts when switching to new version (simulated)
        // In a real test, you would trigger an update scenario that starts the timer

        // For now, just verify the timer can be controlled
        XCTAssertFalse(timer.isRunning)

        // Simulate timer starting
        timer.start(withTimeInterval: 30.0)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.startedWithInterval, 30.0)

        // Simulate timeout
        timer.fireNow()

        // In a real scenario, this would trigger reversion logic
        // For now, we've demonstrated timer control
    }

    /// Example: Testing isolated UserDefaults
    func testIsolatedUserDefaults() async throws {
        let (dependencies1, mocks1) = try TestDependencyFactory.createTestDependencies(userDefaultsSuiteName: "test-suite-1")
        let (dependencies2, mocks2) = try TestDependencyFactory.createTestDependencies(userDefaultsSuiteName: "test-suite-2")
        defer {
            mocks1.cleanup()
            mocks2.cleanup()
        }

        // Each webapp should have isolated configuration
        let config1 = dependencies1.configuration
        let config2 = dependencies2.configuration

        // Set different values
        config1.appId = "app1"
        config2.appId = "app2"

        // Verify isolation
        XCTAssertEqual(config1.appId, "app1")
        XCTAssertEqual(config2.appId, "app2")
        XCTAssertNotEqual(config1.appId, config2.appId)
    }

    // MARK: - Helper Methods

    /// Create a minimal valid bundle for testing
    private func createMinimalWwwBundle(at wwwURL: URL) throws {
        let manifestContent = """
        {
            "format": "web-program-pre1",
            "version": "test-version-1.0",
            "cordovaCompatibilityVersions": {
                "ios": "1.5.0"
            },
            "manifest": [
                {
                    "path": "index.html",
                    "url": "/index.html",
                    "type": "text/html",
                    "hash": "abc123",
                    "cacheable": true,
                    "where": "client"
                }
            ]
        }
        """

        let indexContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test App</title>
            <script type="text/javascript">
                __meteor_runtime_config__ = {
                    "ROOT_URL": "http://localhost:3000/",
                    "appId": "test-app-id",
                    "autoupdateVersionCordova": "1.0.0"
                };
            </script>
        </head>
        <body><h1>Test</h1></body>
        </html>
        """

        // Write manifest
        let manifestURL = wwwURL.appendingPathComponent("program.json")
        try manifestContent.data(using: .utf8)?.write(to: manifestURL)

        // Write index.html
        let indexURL = wwwURL.appendingPathComponent("index.html")
        try indexContent.data(using: .utf8)?.write(to: indexURL)
    }
}
