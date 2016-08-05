import XCTest
import Nimble
import OHHTTPStubs
import Wolf

class CacheNetworkingTests: XCTestCase {
    private let client = TestClient()

    func testThatObjectRequestsAreCached() {
        stub(isPath("/get/user")) { _ in
            return fixture(OHPathForFile("user.json", self.dynamicType)!, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUser(cache: cache)

        waitUntil { done in
            self.client.sendRequest(resource) { response in
                let cachedResponse = cache.cachedResponseForRequest(response.request!)
                expect(cachedResponse?.storagePolicy) == .AllowedInMemoryOnly
                done()
            }
        }
    }

    func testThatArrayRequestsAreCached() {
        stub(isPath("/get/users")) { _ in
            return fixture(OHPathForFile("users.json", self.dynamicType)!, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUsers(cache: cache)

        waitUntil { done in
            self.client.sendArrayRequest(resource) { response in
                let cachedResponse = cache.cachedResponseForRequest(response.request!)
                expect(cachedResponse?.storagePolicy) == .AllowedInMemoryOnly
                done()
            }
        }
    }

    func testThatFailedObjectRequestsAreNotCached() {
        stub(isPath("/get/user")) { _ in
            return OHHTTPStubsResponse(data: NSData(), statusCode: 500, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUser(cache: cache)

        waitUntil { done in
            self.client.sendRequest(resource) { response in
                let cachedResponse = cache.cachedResponseForRequest(response.request!)
                expect(cachedResponse).to(beNil())
                done()
            }
        }
    }

    func testThatFailedArrayRequestsAreNotCached() {
        stub(isPath("/get/users")) { _ in
            return fixture(OHPathForFile("invalid_json.json", self.dynamicType)!, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUsers(cache: cache)

        waitUntil { done in
            self.client.sendArrayRequest(resource) { response in
                let cachedResponse = cache.cachedResponseForRequest(response.request!)
                expect(cachedResponse).to(beNil())
                done()
            }
        }
    }

    func testThatNonExpiredCachedObjectRequestsAreReturned() {
        stub(isPath("/get/user")) { _ in
            return fixture(OHPathForFile("invalid_json.json", self.dynamicType)!, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUser(cache: cache)
        let validJSON = NSData(contentsOfFile: OHPathForFile("user.json", self.dynamicType)!)!
        let cachedResponse = CachedResponse(response: NSURLResponse(), data: validJSON, duration: 30)

        cachedResponse.store(for: client.request(resource).request!, cache: cache)

        waitUntil { done in
            self.client.sendRequest(resource) { response in
                expect(response.result.value?.username) == "fellipecaetano"
                done()
            }
        }
    }

    func testThatNonExpiredCachedArrayRequestsAreReturned() {
        stub(isPath("/get/users")) { _ in
            return fixture(OHPathForFile("invalid_user.json", self.dynamicType)!, headers: nil)
        }

        let validJSON = NSData(contentsOfFile: OHPathForFile("users.json", self.dynamicType)!)!
        let cachedResponse = CachedResponse(response: NSURLResponse(), data: validJSON, duration: 30)
        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUsers(cache: cache)

        cachedResponse.store(for: client.request(resource).request!, cache: cache)

        waitUntil { done in
            self.client.sendArrayRequest(resource) { response in
                expect(response.result.value?.count) == 3
                done()
            }
        }
    }

    func testThatExpiredCachedObjectRequestsAreSkipped() {
        stub(isPath("/get/user")) { _ in
            return fixture(OHPathForFile("invalid_json.json", self.dynamicType)!, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUser(cache: cache)
        let validJSON = NSData(contentsOfFile: OHPathForFile("user.json", self.dynamicType)!)!
        let cachedResponse = CachedResponse(response: NSURLResponse(),
                                            data: validJSON,
                                            duration: resource.cacheDuration,
                                            creationDate: NSDate(timeIntervalSinceNow: resource.cacheDuration + 1))

        cachedResponse.store(for: client.request(resource).request!, cache: cache)

        waitUntil { done in
            self.client.sendRequest(resource) { response in
                expect(response.result.value).to(beNil())
                expect(response.result.error).toNot(beNil())
                done()
            }
        }
    }

    func testThatExpiredCachedArrayRequestsAreSkipped() {
        stub(isPath("/get/users")) { _ in
            return fixture(OHPathForFile("invalid_user.json", self.dynamicType)!, headers: nil)
        }

        let cache = TestURLCache()
        let resource = User.CacheableResource.getCachedUsers(cache: cache)
        let validJSON = NSData(contentsOfFile: OHPathForFile("users.json", self.dynamicType)!)!
        let cachedResponse = CachedResponse(response: NSURLResponse(),
                                            data: validJSON,
                                            duration: resource.cacheDuration,
                                            creationDate: NSDate(timeIntervalSinceNow: resource.cacheDuration + 1))

        cachedResponse.store(for: client.request(resource).request!, cache: cache)

        waitUntil { done in
            self.client.sendArrayRequest(resource) { response in
                expect(response.result.value).to(beNil())
                expect(response.result.error).toNot(beNil())
                done()
            }
        }
    }
}

private extension User {
    enum CacheableResource: HTTPResource, Wolf.CacheableResource {
        typealias Value = User
        typealias Error = ArgoResponseError

        case getCachedUser(cache: URLCache)
        case getCachedUsers(cache: URLCache)

        var path: String {
            switch self {
            case .getCachedUser:
                return "get/user"
            case .getCachedUsers:
                return "get/users"
            }
        }

        var cache: URLCache {
            switch self {
            case .getCachedUser(let cache):
                return cache
            case .getCachedUsers(let cache):
                return cache
            }
        }

        var cacheStoragePolicy: NSURLCacheStoragePolicy {
            return .AllowedInMemoryOnly
        }

        var cacheDuration: NSTimeInterval {
            return 15
        }
    }
}

private class TestURLCache: URLCache {
    var cachedResponses: [NSURL: NSCachedURLResponse] = [:]

    func storeCachedResponse(cachedResponse: NSCachedURLResponse, forRequest request: NSURLRequest) {
        cachedResponses[request.URL!] = cachedResponse
    }

    private func cachedResponseForRequest(request: NSURLRequest) -> NSCachedURLResponse? {
        return cachedResponses[request.URL!]
    }
}