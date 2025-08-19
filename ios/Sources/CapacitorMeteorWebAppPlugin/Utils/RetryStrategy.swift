//
// RetryStrategy.swift
//
// Implements exponential backoff retry logic for network operations
// with configurable timing and randomization.
//
// This file is ported from METRetryStrategy.m in cordova-plugin-meteor-webapp,
// translated from Objective-C to Swift for Capacitor.
//

import Foundation

final class RetryStrategy {
    var minimumTimeInterval: TimeInterval = 0.1
    var maximumTimeInterval: TimeInterval = 30.0
    var numberOfAttemptsAtMinimumTimeInterval: UInt = 2
    var baseTimeInterval: TimeInterval = 1.0
    var exponent: Double = 2.2
    var randomizationFactor: Double = 0.5

    func retryIntervalForNumber(ofAttempts numberOfAttempts: UInt) -> TimeInterval {
        if numberOfAttempts < numberOfAttemptsAtMinimumTimeInterval {
            return minimumTimeInterval
        }

        let interval =
            baseTimeInterval
            * pow(exponent, Double(numberOfAttempts - numberOfAttemptsAtMinimumTimeInterval))
        let randomizedInterval =
            interval * (1.0 + randomizationFactor * (Double.random(in: 0...1) * 2.0 - 1.0))

        return min(max(randomizedInterval, minimumTimeInterval), maximumTimeInterval)
    }
}
