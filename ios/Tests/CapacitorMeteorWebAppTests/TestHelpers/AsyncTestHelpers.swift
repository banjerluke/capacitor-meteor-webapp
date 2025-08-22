import Foundation
import XCTest

class AsyncTestHelpers {

    @discardableResult
    static func waitForAsync<T>(
        timeout: TimeInterval = 5.0,
        description: String = "async operation",
        operation: @escaping (@escaping (T) -> Void) -> Void
    ) -> T? {
        let expectation = XCTestExpectation(description: description)
        var result: T?

        operation { value in
            result = value
            expectation.fulfill()
        }

        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: timeout)

        switch waiterResult {
        case .completed:
            return result
        case .timedOut:
            XCTFail("Async operation timed out after \(timeout) seconds")
            return nil
        case .incorrectOrder:
            XCTFail("Async operation completed in incorrect order")
            return nil
        case .invertedFulfillment:
            XCTFail("Async operation had inverted fulfillment")
            return nil
        case .interrupted:
            XCTFail("Async operation was interrupted")
            return nil
        @unknown default:
            XCTFail("Unknown async operation result")
            return nil
        }
    }

    static func waitForCondition(
        timeout: TimeInterval = 5.0,
        description: String = "condition",
        condition: @escaping () -> Bool
    ) -> Bool {
        let expectation = XCTestExpectation(description: description)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if condition() {
                timer.invalidate()
                expectation.fulfill()
            }
        }

        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: timeout)
        timer.invalidate()

        return waiterResult == .completed
    }

    static func executeWithDelay(
        delay: TimeInterval,
        operation: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            operation()
        }
    }

    static func createAsyncExpectation(
        description: String,
        expectedFulfillmentCount: Int = 1
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        expectation.expectedFulfillmentCount = expectedFulfillmentCount
        return expectation
    }

    static func waitForExpectations(
        _ expectations: [XCTestExpectation],
        timeout: TimeInterval = 5.0,
        enforceOrder: Bool = false
    ) -> Bool {
        let waiterResult = XCTWaiter().wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
        return waiterResult == .completed
    }

    static func runAsyncTest<T>(
        timeout: TimeInterval = 10.0,
        description: String = "async test",
        test: @escaping () async throws -> T
    ) -> T? {
        var result: T?
        var error: Error?
        let expectation = XCTestExpectation(description: description)

        Task {
            do {
                result = try await test()
            } catch let thrownError {
                error = thrownError
            }
            expectation.fulfill()
        }

        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if let error = error {
            XCTFail("Async test failed with error: \(error)")
            return nil
        }

        guard waiterResult == .completed else {
            XCTFail("Async test timed out or failed")
            return nil
        }

        return result
    }

    static func simulateNetworkDelay(
        minDelay: TimeInterval = 0.1,
        maxDelay: TimeInterval = 0.5,
        completion: @escaping () -> Void
    ) {
        let randomDelay = TimeInterval.random(in: minDelay...maxDelay)
        DispatchQueue.global().asyncAfter(deadline: .now() + randomDelay) {
            completion()
        }
    }

    static func measureAsyncPerformance<T>(
        description: String = "async performance test",
        iterations: Int = 1,
        operation: @escaping () async throws -> T
    ) -> TimeInterval? {
        let startTime = CFAbsoluteTimeGetCurrent()
        var completedIterations = 0
        let expectation = XCTestExpectation(description: description)
        expectation.expectedFulfillmentCount = iterations

        for _ in 0..<iterations {
            Task {
                do {
                    _ = try await operation()
                    completedIterations += 1
                } catch {
                    XCTFail("Performance test iteration failed: \(error)")
                }
                expectation.fulfill()
            }
        }

        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: 30.0)
        let endTime = CFAbsoluteTimeGetCurrent()

        guard waiterResult == .completed && completedIterations == iterations else {
            XCTFail("Performance test failed to complete all iterations")
            return nil
        }

        return endTime - startTime
    }
}

extension XCTestCase {

    func waitForAsync<T>(
        timeout: TimeInterval = 5.0,
        description: String = "async operation",
        operation: @escaping (@escaping (T) -> Void) -> Void
    ) -> T? {
        return AsyncTestHelpers.waitForAsync(
            timeout: timeout,
            description: description,
            operation: operation
        )
    }

    func waitForCondition(
        timeout: TimeInterval = 5.0,
        description: String = "condition",
        condition: @escaping () -> Bool
    ) -> Bool {
        return AsyncTestHelpers.waitForCondition(
            timeout: timeout,
            description: description,
            condition: condition
        )
    }
}
