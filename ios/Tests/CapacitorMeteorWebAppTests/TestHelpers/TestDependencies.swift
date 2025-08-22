//
// TestDependencies.swift
//
// Test dependencies and mocks for dependency injection testing
//

import Foundation
import XCTest
import WebKit
@testable import CapacitorMeteorWebAppPlugin

// MARK: - Mock Implementations

/// Mock file system for isolated testing
public class MockFileSystem: FileSystemProvider {
    private var existingPaths: Set<String> = []
    private var directories: Set<String> = []

    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        return existingPaths.contains(path)
    }

    public func removeItem(at url: URL) throws {
        existingPaths.remove(url.path)
    }

    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {
        directories.insert(url.path)
    }

    public func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        return [URL(fileURLWithPath: "/tmp/mock-library")]
    }

    // Test helpers
    func addExistingPath(_ path: String) {
        existingPaths.insert(path)
    }

    func isPathMarkedAsCreated(_ path: String) -> Bool {
        return directories.contains(path)
    }
}

/// Mock timer for controlled testing
public class MockTimer: TimerInterface {
    public var isRunning = false
    public var startedWithInterval: TimeInterval?
    public let block: () -> Void

    public init(block: @escaping () -> Void) {
        self.block = block
    }

    public func start(withTimeInterval interval: TimeInterval) {
        startedWithInterval = interval
        isRunning = true
    }

    public func stop() {
        isRunning = false
        startedWithInterval = nil
    }

    public func fireNow() {
        if isRunning {
            block()
        }
    }
}

/// Mock timer provider for creating controlled test timers
public class MockTimerProvider: TimerProvider {
    public var createdTimers: [MockTimer] = []

    public init() {}

    public func createTimer(queue: DispatchQueue?, block: @escaping () -> Void) -> TimerInterface {
        let timer = MockTimer(block: block)
        createdTimers.append(timer)
        return timer
    }
}

/// Mock Capacitor bridge for testing bridge interactions
public class TestMockCapacitorBridge: CapacitorBridge {
    public var setServerBasePathCalls: [String] = []
    public var reloadCalls = 0

    public init() {}

    public func setServerBasePath(_ path: String) {
        setServerBasePathCalls.append(path)
    }

    public func getWebView() -> AnyObject? {
        return nil
    }

    public var webView: WKWebView? {
        return nil
    }

    public func reload() {
        reloadCalls += 1
    }
}

// MARK: - Test Dependency Factory

public class TestDependencyFactory {

    /// Create test dependencies with mock implementations
    public static func createTestDependencies(
        userDefaultsSuiteName: String = "test-\(UUID().uuidString)",
        mockFileSystem: MockFileSystem = MockFileSystem(),
        mockTimerProvider: MockTimerProvider = MockTimerProvider(),
        mockCapacitorBridge: TestMockCapacitorBridge = TestMockCapacitorBridge()
    ) throws -> (dependencies: CapacitorMeteorWebAppDependencies, mocks: TestMocks) {

        // Create temporary directories for testing
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capacitor-meteor-test-\(UUID().uuidString)")
        let wwwDir = tempDir.appendingPathComponent("www")
        let servingDir = tempDir.appendingPathComponent("serving")
        let versionsDir = tempDir.appendingPathComponent("versions")

        // Create the directories on the real file system
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: wwwDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: servingDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: versionsDir, withIntermediateDirectories: true, attributes: nil)

        // Mark them as existing in the mock file system as well
        mockFileSystem.addExistingPath(wwwDir.path)
        mockFileSystem.addExistingPath(servingDir.path)
        mockFileSystem.addExistingPath(versionsDir.path)

        let dependencies = CapacitorMeteorWebAppDependencies.test(
            capacitorBridge: mockCapacitorBridge,
            userDefaultsSuiteName: userDefaultsSuiteName,
            wwwDirectoryURL: wwwDir,
            servingDirectoryURL: servingDir,
            versionsDirectoryURL: versionsDir,
            fileSystem: mockFileSystem,
            timerProvider: mockTimerProvider
        )

        let mocks = TestMocks(
            fileSystem: mockFileSystem,
            timerProvider: mockTimerProvider,
            capacitorBridge: mockCapacitorBridge,
            tempDir: tempDir
        )

        return (dependencies, mocks)
    }
}

/// Container for all test mocks
public struct TestMocks {
    public let fileSystem: MockFileSystem
    public let timerProvider: MockTimerProvider
    public let capacitorBridge: TestMockCapacitorBridge
    public let tempDir: URL

    /// Clean up temporary test files
    public func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }
}
