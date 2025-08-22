//
// CapacitorMeteorWebAppDependencies.swift
//
// Dependency injection interfaces and implementations for CapacitorMeteorWebApp
//

import Foundation

// MARK: - File System Protocol

public protocol FileSystemProvider {
    func fileExists(atPath path: String) -> Bool
    func removeItem(at URL: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL]
}

extension FileManager: FileSystemProvider {}

// MARK: - Timer Protocol

public protocol TimerProvider {
    func createTimer(queue: DispatchQueue?, block: @escaping () -> Void) -> TimerInterface
}

public protocol TimerInterface {
    func start(withTimeInterval interval: TimeInterval)
    func stop()
}

// Default implementation using real Timer
public class SystemTimerProvider: TimerProvider {
    public init() {}

    public func createTimer(queue: DispatchQueue?, block: @escaping () -> Void) -> TimerInterface {
        return TimerWrapper(timer: Timer(queue: queue ?? DispatchQueue.main, block: block))
    }
}

// Wrapper to adapt the existing Timer class to TimerInterface
public class TimerWrapper: TimerInterface {
    private let timer: Timer

    public init(timer: Timer) {
        self.timer = timer
    }

    public func start(withTimeInterval interval: TimeInterval) {
        timer.start(withTimeInterval: interval)
    }

    public func stop() {
        timer.stop()
    }
}

// MARK: - Bundle Provider Protocol

public protocol BundleProvider {
    var resourceURL: URL? { get }
    var mainBundle: BundleProvider { get }
}

extension Bundle: BundleProvider {
    public var mainBundle: BundleProvider { return Bundle.main }
}

// MARK: - Dependencies Container

public struct CapacitorMeteorWebAppDependencies {
    public let configuration: WebAppConfiguration
    public let fileSystem: FileSystemProvider
    public let timerProvider: TimerProvider
    public let bundleProvider: BundleProvider
    public let capacitorBridge: CapacitorBridge?
    public let wwwDirectoryURL: URL
    public let servingDirectoryURL: URL
    public let versionsDirectoryURL: URL
    public let urlSessionConfiguration: URLSessionConfiguration

    public init(
        configuration: WebAppConfiguration,
        fileSystem: FileSystemProvider,
        timerProvider: TimerProvider,
        bundleProvider: BundleProvider,
        capacitorBridge: CapacitorBridge?,
        wwwDirectoryURL: URL,
        servingDirectoryURL: URL,
        versionsDirectoryURL: URL,
        urlSessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.configuration = configuration
        self.fileSystem = fileSystem
        self.timerProvider = timerProvider
        self.bundleProvider = bundleProvider
        self.capacitorBridge = capacitorBridge
        self.wwwDirectoryURL = wwwDirectoryURL
        self.servingDirectoryURL = servingDirectoryURL
        self.versionsDirectoryURL = versionsDirectoryURL
        self.urlSessionConfiguration = urlSessionConfiguration
    }

    // Default production dependencies
    public static func production(
        capacitorBridge: CapacitorBridge? = nil,
        wwwDirectoryName: String = "public"
    ) throws -> CapacitorMeteorWebAppDependencies {

        let configuration = WebAppConfiguration()
        let fileSystem = FileManager.default
        let timerProvider = SystemTimerProvider()
        let bundleProvider = Bundle.main

        // Set www directory URL - check if it exists first
        guard let resourceURL = bundleProvider.resourceURL else {
            throw HotCodePushError.initializationFailed(reason: "Could not get main bundle resource URL")
        }

        let publicURL = resourceURL.appendingPathComponent("public")
        let wwwURL = resourceURL.appendingPathComponent("www")

        let wwwDirectoryURL: URL
        if fileSystem.fileExists(atPath: publicURL.path) {
            wwwDirectoryURL = publicURL
        } else if fileSystem.fileExists(atPath: wwwURL.path) {
            wwwDirectoryURL = wwwURL
        } else {
            throw HotCodePushError.initializationFailed(reason: "Neither public nor www directory exists in bundle")
        }

        guard let libraryDirectoryURL = fileSystem.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw HotCodePushError.initializationFailed(reason: "Could not get library directory URL")
        }

        let versionsDirectoryURL = libraryDirectoryURL.appendingPathComponent("NoCloud/meteor")
        let servingDirectoryURL = libraryDirectoryURL.appendingPathComponent("NoCloud/meteor-serving")

        return CapacitorMeteorWebAppDependencies(
            configuration: configuration,
            fileSystem: fileSystem,
            timerProvider: timerProvider,
            bundleProvider: bundleProvider,
            capacitorBridge: capacitorBridge,
            wwwDirectoryURL: wwwDirectoryURL,
            servingDirectoryURL: servingDirectoryURL,
            versionsDirectoryURL: versionsDirectoryURL,
            urlSessionConfiguration: .default
        )
    }

    // Test dependencies with isolated storage
    public static func test(
        capacitorBridge: CapacitorBridge? = nil,
        userDefaultsSuiteName: String = "test",
        wwwDirectoryURL: URL,
        servingDirectoryURL: URL,
        versionsDirectoryURL: URL,
        fileSystem: FileSystemProvider = FileManager.default,
        timerProvider: TimerProvider = SystemTimerProvider(),
        urlSessionConfiguration: URLSessionConfiguration = .default
    ) -> CapacitorMeteorWebAppDependencies {

        let configuration = WebAppConfiguration(userDefaultsSuiteName: userDefaultsSuiteName)

        return CapacitorMeteorWebAppDependencies(
            configuration: configuration,
            fileSystem: fileSystem,
            timerProvider: timerProvider,
            bundleProvider: Bundle.main, // Can be mocked if needed
            capacitorBridge: capacitorBridge,
            wwwDirectoryURL: wwwDirectoryURL,
            servingDirectoryURL: servingDirectoryURL,
            versionsDirectoryURL: versionsDirectoryURL,
            urlSessionConfiguration: urlSessionConfiguration
        )
    }
}
