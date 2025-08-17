import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(CapacitorMeteorWebAppPlugin)
public class CapacitorMeteorWebAppPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CapacitorMeteorWebAppPlugin"
    public let jsName = "CapacitorMeteorWebApp"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = CapacitorMeteorWebApp()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }
}
