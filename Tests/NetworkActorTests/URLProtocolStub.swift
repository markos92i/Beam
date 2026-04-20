
import Foundation
@testable import NetworkActor

class URLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs = [Stub]()

    static func addStub(endpoint: EndpointMock, handler: @escaping () -> StubResponse) {
        let stub = Stub(matcher: { endpoint.match(request: $0) }, handler: handler)

        lock.lock()
        stubs.append(stub)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = getStub(for: request) else { return }
        defer { removeStub(for: request) }

        let stubResponse = stub.handler()

        if let data = stubResponse.data {
            client?.urlProtocol(self, didLoad: data)
        }

        if let response = stubResponse.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        if let error = stubResponse.error {
            client?.urlProtocol(self, didFailWithError: error)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func getStub(for request: URLRequest) -> Stub? {
        URLProtocolStub.lock.lock()
        let stub = URLProtocolStub.stubs.first { $0.matcher(request) }
        URLProtocolStub.lock.unlock()

        return stub
    }

    private func removeStub(for request: URLRequest) {
        URLProtocolStub.lock.lock()
        if let index = URLProtocolStub.stubs.firstIndex(where: { stub in stub.matcher(request) }) {
            URLProtocolStub.stubs.remove(at: index)
        }
        URLProtocolStub.lock.unlock()
    }
}

private struct Stub {
    let matcher: (URLRequest) -> Bool
    let handler: () -> StubResponse
}

struct StubResponse {
    let data: Data?
    let response: URLResponse?
    let error: NetworkErrorType?
}

struct EndpointMock {
    private let id = UUID()
    private let endpoint: ServicePayload

    init(endpoint: ServicePayload) {
        self.endpoint = endpoint
    }

    var method: HTTPMethod { endpoint.method }
    var baseURL: String { endpoint.baseURL }
    var path: String { endpoint.path }
    var params: [URLQueryItem] { endpoint.params }
    var headers: [String: String] { endpoint.headers.merging(["mock-header-id" : id.uuidString]) { $1 } }
    var body: Sendable? { endpoint.body }
    var data: Data? { endpoint.data }
    var timeout: TimeInterval { endpoint.timeout }

    func match(request: URLRequest) -> Bool {
        request.allHTTPHeaderFields?["mock-header-id"] == id.uuidString
    }
    
    var api: ServicePayload {
        .init(method: method, baseURL: baseURL, path: path, params: params, headers: headers, body: body, data: data, timeout: timeout)
    }
}

extension EndpointMock {
    var url: URL? {
        var urlComponents = URLComponents(string: baseURL + path)
        if urlComponents?.queryItems != nil {
            urlComponents?.queryItems?.append(contentsOf: params)
        } else {
            urlComponents?.queryItems = params
        }
        return urlComponents?.url
    }
}
