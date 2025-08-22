import Foundation

class MockMeteorServerProtocol: URLProtocol {
    static var mockResponses: [String: MockResponse] = [:]
    static var receivedRequests: [URLRequest] = []

    struct MockResponse {
        let data: Data?
        let statusCode: Int
        let headers: [String: String]?

        init(data: Data? = nil, statusCode: Int = 200, headers: [String: String]? = nil) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              let scheme = url.scheme else { return false }

        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockMeteorServerProtocol.receivedRequests.append(request)

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockError", code: -1))
            return
        }

        let urlString = url.absoluteString

        if let mockResponse = MockMeteorServerProtocol.mockResponses[urlString] {
            let response = HTTPURLResponse(
                url: url,
                statusCode: mockResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: mockResponse.headers
            )!

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            if let data = mockResponse.data {
                client?.urlProtocol(self, didLoad: data)
            }

            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
    }

    static func reset() {
        mockResponses.removeAll()
        receivedRequests.removeAll()
    }

    static func setMockResponse(for urlString: String, response: MockResponse) {
        mockResponses[urlString] = response
    }

    static func setMockManifest(baseURL: String, version: String, manifest: [String: Any]) {
        let manifestURL = "\(baseURL)/__cordova/manifest.json"

        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [])
            setMockResponse(for: manifestURL, response: MockResponse(data: data))
        } catch {
            print("Error serializing manifest: \(error)")
        }
    }

    static func setMockAsset(baseURL: String, path: String, content: String) {
        let assetURL = "\(baseURL)/__cordova/\(path)"
        let data = content.data(using: .utf8)
        setMockResponse(for: assetURL, response: MockResponse(data: data))
    }

    static func serveVersion(_ version: String, baseURL: String = "http://localhost:3000") {
        reset()

        switch version {
        case "version1":
            setMockManifest(baseURL: baseURL, version: "version1", manifest: [
                "version": "version1",
                "versionRefreshable": "version1",
                "versionNonRefreshable": "version1",
                "appId": "test-app-id",
                "autoupdateVersion": "1.2.3",
                "autoupdateVersionRefreshable": "1.2.3",
                "autoupdateVersionCordova": "1.2.3",
                "appVersions": ["1.0.0"],
                "cordova": ["1.0.0"],
                "reloadUrlOnResume": true,
                "hmrAvailable": false,
                "assets": [
                    [
                        "url": "/",
                        "size": 1024,
                        "hash": "index-hash-v1",
                        "path": "index.html"
                    ],
                    [
                        "url": "/some-file",
                        "size": 512,
                        "hash": "some-file-hash-v1",
                        "path": "app/some-file"
                    ],
                    [
                        "url": "/packages/meteor.js",
                        "size": 2048,
                        "hash": "meteor-js-hash-v1",
                        "path": "app/packages/meteor.js"
                    ]
                ]
            ])

            setMockAsset(baseURL: baseURL, path: "", content: "<html><head><title>Test App v1</title></head><body>Version 1</body></html>")
            setMockAsset(baseURL: baseURL, path: "app/some-file", content: "some-file content v1")
            setMockAsset(baseURL: baseURL, path: "app/packages/meteor.js", content: "// meteor.js v1")

        case "version2":
            setMockManifest(baseURL: baseURL, version: "version2", manifest: [
                "version": "version2",
                "versionRefreshable": "version2",
                "versionNonRefreshable": "version2",
                "appId": "test-app-id",
                "autoupdateVersion": "1.2.4",
                "autoupdateVersionRefreshable": "1.2.4",
                "autoupdateVersionCordova": "1.2.4",
                "appVersions": ["1.0.0"],
                "cordova": ["1.0.0"],
                "reloadUrlOnResume": true,
                "hmrAvailable": false,
                "assets": [
                    [
                        "url": "/",
                        "size": 1024,
                        "hash": "index-hash-v2",
                        "path": "index.html"
                    ],
                    [
                        "url": "/some-file",
                        "size": 512,
                        "hash": "some-file-hash-v2",
                        "path": "app/some-file"
                    ],
                    [
                        "url": "/some-other-file",
                        "size": 256,
                        "hash": "some-other-file-hash-v2",
                        "path": "app/some-other-file"
                    ],
                    [
                        "url": "/packages/meteor.js",
                        "size": 2048,
                        "hash": "meteor-js-hash-v1",
                        "path": "app/packages/meteor.js"
                    ],
                    [
                        "url": "/template.mobileapp.js",
                        "size": 1536,
                        "hash": "template-hash-v2",
                        "path": "app/template.mobileapp.js"
                    ]
                ]
            ])

            setMockAsset(baseURL: baseURL, path: "", content: "<html><head><title>Test App v2</title></head><body>Version 2</body></html>")
            setMockAsset(baseURL: baseURL, path: "app/some-file", content: "some-file content v2")
            setMockAsset(baseURL: baseURL, path: "app/some-other-file", content: "some-other-file content v2")
            setMockAsset(baseURL: baseURL, path: "app/packages/meteor.js", content: "// meteor.js v1")
            setMockAsset(baseURL: baseURL, path: "app/template.mobileapp.js", content: "// template.mobileapp.js v2")

        default:
            break
        }
    }
}
