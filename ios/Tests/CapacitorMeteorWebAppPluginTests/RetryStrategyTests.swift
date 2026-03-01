import XCTest

@testable import CapacitorMeteorWebAppPlugin

final class RetryStrategyTests: XCTestCase {

    func testTriangularBackoffMatchesExpectedIntervals() {
        let strategy = RetryStrategy()
        // Expected sequence: 0.1, 1, 2, 4, 7, 11, 16, 22, 30, 30
        let expected: [TimeInterval] = [0.1, 1, 2, 4, 7, 11, 16, 22, 30, 30]

        for (attempt, expectedInterval) in expected.enumerated() {
            let actual = strategy.retryIntervalForNumber(ofAttempts: UInt(attempt))
            XCTAssertEqual(actual, expectedInterval, accuracy: 0.001,
                "Attempt \(attempt): expected \(expectedInterval), got \(actual)")
        }
    }
}
