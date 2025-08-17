import Foundation

final class WebAppConfiguration {
    private let userDefaults = UserDefaults.standard
    
    // State keys following the exact Cordova pattern
    private let lastDownloadedVersionKey = "MeteorWebAppLastDownloadedVersion"
    private let lastKnownGoodVersionKey = "MeteorWebAppLastKnownGoodVersion"
    private let blacklistedVersionsKey = "MeteorWebAppBlacklistedVersions"
    private let lastSeenInitialVersionKey = "MeteorWebAppLastSeenInitialVersion"
    private let versionsToRetryKey = "MeteorWebAppVersionsToRetry"
    private let appIdKey = "MeteorWebAppId"
    private let rootURLKey = "MeteorWebAppRootURL"
    private let cordovaCompatibilityVersionKey = "MeteorWebAppCordovaCompatibilityVersion"
    
    /// The appId as defined in the runtime config
    var appId: String? {
        get {
            return userDefaults.string(forKey: appIdKey)
        }
        set {
            let oldValue = appId
            if newValue != oldValue && newValue != nil {
                if oldValue != nil {
                    NSLog("appId seems to have changed, new: \(newValue!), old: \(oldValue!)")
                }
                userDefaults.set(newValue!, forKey: appIdKey)
            }
        }
    }
    
    /// The rootURL as defined in the runtime config
    var rootURL: URL? {
        get {
            guard let urlString = userDefaults.string(forKey: rootURLKey) else { return nil }
            return URL(string: urlString)
        }
        set {
            let oldValue = rootURL
            if newValue != oldValue && newValue != nil {
                if oldValue != nil {
                    NSLog("ROOT_URL seems to have changed, new: \(newValue!), old: \(oldValue!)")
                }
                userDefaults.set(newValue!.absoluteString, forKey: rootURLKey)
            }
        }
    }
    
    /// The Cordova compatibility version as specified in the asset manifest
    var cordovaCompatibilityVersion: String? {
        get {
            return userDefaults.string(forKey: cordovaCompatibilityVersionKey)
        }
        set {
            if newValue != cordovaCompatibilityVersion {
                if newValue == nil {
                    userDefaults.removeObject(forKey: cordovaCompatibilityVersionKey)
                } else {
                    userDefaults.set(newValue!, forKey: cordovaCompatibilityVersionKey)
                }
            }
        }
    }
    
    /// The last seen initial version of the asset bundle
    var lastSeenInitialVersion: String? {
        get {
            return userDefaults.string(forKey: lastSeenInitialVersionKey)
        }
        set {
            if newValue != lastSeenInitialVersion {
                if newValue == nil {
                    userDefaults.removeObject(forKey: lastSeenInitialVersionKey)
                } else {
                    userDefaults.set(newValue!, forKey: lastSeenInitialVersionKey)
                }
            }
        }
    }
    
    /// The last downloaded version of the asset bundle
    var lastDownloadedVersion: String? {
        get {
            return userDefaults.string(forKey: lastDownloadedVersionKey)
        }
        set {
            if newValue != lastDownloadedVersion {
                if newValue == nil {
                    userDefaults.removeObject(forKey: lastDownloadedVersionKey)
                } else {
                    userDefaults.set(newValue!, forKey: lastDownloadedVersionKey)
                }
            }
        }
    }
    
    /// The last known good version of the asset bundle
    var lastKnownGoodVersion: String? {
        get {
            return userDefaults.string(forKey: lastKnownGoodVersionKey)
        }
        set {
            if newValue != lastKnownGoodVersion {
                if newValue == nil {
                    userDefaults.removeObject(forKey: lastKnownGoodVersionKey)
                } else {
                    userDefaults.set(newValue!, forKey: lastKnownGoodVersionKey)
                }
            }
        }
    }
    
    /// Blacklisted asset bundle versions
    var blacklistedVersions: [String] {
        get {
            let versions = userDefaults.array(forKey: blacklistedVersionsKey) as? [String] ?? []
            NSLog("BLACKLIST - blacklistedVersions: \(versions)")
            return versions
        }
        set {
            if newValue != blacklistedVersions {
                if newValue.isEmpty {
                    NSLog("BLACKLIST - removing blacklisted versions")
                    userDefaults.removeObject(forKey: blacklistedVersionsKey)
                } else {
                    userDefaults.set(newValue, forKey: blacklistedVersionsKey)
                }
            }
        }
    }
    
    /// Versions to retry before blacklisting
    var versionsToRetry: [String] {
        get {
            let versions = userDefaults.array(forKey: versionsToRetryKey) as? [String] ?? []
            NSLog("BLACKLIST - versionsToRetry: \(versions)")
            return versions
        }
        set {
            if newValue != versionsToRetry {
                if newValue.isEmpty {
                    NSLog("BLACKLIST - removing versions to retry")
                    userDefaults.removeObject(forKey: versionsToRetryKey)
                } else {
                    userDefaults.set(newValue, forKey: versionsToRetryKey)
                }
            }
        }
    }
    
    /// Add a version to blacklist or retry list based on retry status
    func addBlacklistedVersion(_ version: String) {
        var blacklistedVersions = self.blacklistedVersions
        var versionsToRetry = self.versionsToRetry
        
        if (!versionsToRetry.contains(version) && !blacklistedVersions.contains(version)) {
            NSLog("BLACKLIST - adding faulty version to retry: \(version)")
            versionsToRetry.append(version)
            self.versionsToRetry = versionsToRetry
        } else {
            if let index = versionsToRetry.firstIndex(of: version) {
                versionsToRetry.remove(at: index)
                self.versionsToRetry = versionsToRetry
            }
            if (!blacklistedVersions.contains(version)) {
                blacklistedVersions.append(version)
                NSLog("BLACKLIST - blacklisting version: \(version)")
                self.blacklistedVersions = blacklistedVersions
            }
        }
    }
    
    /// Reset all configuration state
    func reset() {
        cordovaCompatibilityVersion = nil
        lastSeenInitialVersion = nil
        lastDownloadedVersion = nil
        lastKnownGoodVersion = nil
        blacklistedVersions = []
        versionsToRetry = []
    }
}
