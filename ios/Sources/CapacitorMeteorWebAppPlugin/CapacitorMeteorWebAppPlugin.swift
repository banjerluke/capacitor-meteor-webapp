import Foundation

// For standalone compilation without Capacitor dependency
#if canImport(Capacitor)
import Capacitor

// Bridge adapter to implement our protocol with Capacitor
class CapacitorBridgeAdapter: CapacitorBridge {
    weak var bridge: CAPBridgeProtocol?

    init(bridge: CAPBridgeProtocol?) {
        self.bridge = bridge
    }

    func setServerBasePath(_ path: String) {
        bridge?.setServerBasePath(path)
    }

    func getWebView() -> AnyObject? {
        return bridge?.webView
    }

    var webView: WKWebView? {
        return bridge?.webView
    }
    
    func reload() {
        // CAPBridgeProtocol doesn't have a reload method, so we reload the webView directly
        bridge?.webView?.reload()
    }
}

/**
 * Capacitor MeteorWebapp Plugin
 * Enables hot code push functionality for Meteor apps
 */
@objc(CapacitorMeteorWebAppPlugin)
public class CapacitorMeteorWebAppPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CapacitorMeteorWebAppPlugin"
    public let jsName = "MeteorWebapp"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "checkForUpdates", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startupDidComplete", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentVersion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isUpdateAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "reload", returnType: CAPPluginReturnPromise)
    ]
    private var implementation: CapacitorMeteorWebApp!

    override public func load() {
        let bridgeAdapter = CapacitorBridgeAdapter(bridge: self.bridge)
        implementation = CapacitorMeteorWebApp(capacitorBridge: bridgeAdapter)
    }

    @objc func checkForUpdates(_ call: CAPPluginCall) {
        implementation.checkForUpdates { error in
            if let error = error {
                call.reject(error.localizedDescription)
            } else {
                call.resolve()
            }
        }
    }

    @objc func startupDidComplete(_ call: CAPPluginCall) {
        implementation.startupDidComplete { error in
            if let error = error {
                call.reject(error.localizedDescription)
            } else {
                call.resolve()
            }
        }
    }

    @objc func getCurrentVersion(_ call: CAPPluginCall) {
        let version = implementation.getCurrentVersion()
        call.resolve(["version": version])
    }

    @objc func isUpdateAvailable(_ call: CAPPluginCall) {
        let available = implementation.isUpdateAvailable()
        call.resolve(["available": available])
    }

    @objc func reload(_ call: CAPPluginCall) {
        implementation.reload { error in
            if let error = error {
                call.reject(error.localizedDescription)
            } else {
                call.resolve()
            }
        }
    }
}
#else
// Fallback stub for standalone compilation
@objc(CapacitorMeteorWebAppPlugin)
public class CapacitorMeteorWebAppPlugin: NSObject {
    public let identifier = "CapacitorMeteorWebAppPlugin"
    public let jsName = "MeteorWebapp"

    public override init() {
        super.init()
        print("CapacitorMeteorWebAppPlugin: Capacitor not available, plugin disabled")
    }
}
#endif
