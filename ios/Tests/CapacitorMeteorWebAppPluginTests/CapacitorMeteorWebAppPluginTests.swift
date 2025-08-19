//
// CapacitorMeteorWebAppPluginTests.swift
//
// Unit tests for the Capacitor Meteor webapp plugin.
//

import XCTest

@testable import CapacitorMeteorWebAppPlugin

class CapacitorMeteorWebAppTests: XCTestCase {
    func testEcho() {
        // This is an example of a functional test case for a plugin.
        // Use XCTAssert and related functions to verify your tests produce the correct results.

        let implementation = CapacitorMeteorWebApp()
        let value = "Hello, World!"
        let result = implementation.echo(value)

        XCTAssertEqual(value, result)
    }
}
