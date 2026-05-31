# Declarative Network Layer (DSL HTTP Client)

This module implements the core network communication engine for the application. It has been built using a **declarative, value-oriented (`struct`) approach** powered by Swift's `resultBuilders`. 

The system guarantees type safety, strict dependency inversion, complete isolation against global naming collisions, and compile-time validation rules.

---

## 🎯 Architecture Pillars

### 1. Compile-Time Validation (Zero Runtime Routing Errors)
The DSL utilizes static type constraints. The `DSLBuilder` enforces by signature that the very first element of the declarative block must be an HTTP method (`NetworkDSL.Method`). If a developer attempts to construct a request and forgets the verb (`Get`, `Post`, etc.), **Xcode will stop compilation in real time**, preventing human errors from reaching production.

### 2. Robust Data Mapping (Mapper)
The transformation of raw network bytes into domain models is managed via the **`Mapper`** component (aligned with industry standards found in major frameworks like Alamofire or Moya). The underlying `Serializer` has been hardened by removing optional returns: it guarantees a strongly-typed result or explicitly throws `.unsupported` or `.incorrect` exceptions (the latter when physical bytes do not match the inferred generic type).

---

## 🧬 Data Flow Architecture

When `.build()` is invoked on a `RequestBuilder`, the immutable configuration tree is processed through the following hierarchy:

---

## 🛠️ DSL Components Reference

### HTTP Methods (Mandatory on the first line)
* `Get(host:path:)`, `Post(host:path:)`, `Put(host:path:)`, `Delete(host:path:)`, `Patch(host:path:)`, `Head(host:path:)`, `Options(host:path:)`, `Connect(host:path:)`, `Trace(host:path:)`.

### Request Modifiers
* `Header(_ key: String, value: String)`: Appends an individual key-value header.
* `Header(_ dictionary: [String: String])`: Dynamically merges an entire dictionary of base configurations (e.g., `APIConstants.headers`).
* `Query(_ name: String, value: String?)`: Sequentially appends a `URLQueryItem`.
* `Body`: Syntax namespace to attach request payloads via `Body.json(Sendable)`, `Body.data(Data)`, or `Body.multipart(MultipartForm)`.
* `Timeout(_ interval: TimeInterval)`: Sets the maximum request execution time (defaults to 60 seconds).

### Infrastructure & Injection Components
* `Use(any NetworkProtocol)`: Overrides the default network client (ideal for injecting `SSL Pinning` certificates or custom `MockSession` environments).
* `Config(ServiceConfig)`: Injects service policies and configurations.
* `Mapper(Serializer)`: Attaches a serializer with custom encoding/decoding strategies (e.g., Unix timestamps or *snake_case* keys).
* `Auth(any AuthProtocol)`: Injects the session/authentication token manager.
* `Crash(any CrashProtocol)`: Injects the analytical crash and error reporter.

---

## 🚀 Usage Guide

### 1. Standard Service Implementation

Endpoints can be encapsulated into structures conforming to `ServiceProtocol`. This isolates networking logic completely from the Presentation Layer.

```swift
import Foundation

struct DeleteService: ServiceProtocol {
    var service: Service<Void, ErrorDto>

    init(id: String) {
        self.service = RequestBuilder {
            // 1. HTTP Method MUST be on the first line (Real-time compilation validation)
            Delete(URLs.api, "/users/\(id)")
            
            // 2. Merged headers (Accepts full dictionaries)
            Header([["Header1": "Value1"], ["Header2": "Value1"]])
            Header("X-Device-Client", value: "iOS")
            
            // 3. Network infrastructure with custom SSL Pinning certificates
            Use(NetworkClient(certificates: [CertificateData]))
            
            // 4. Configuration & Timeouts
            Config(.standard)
            Timeout(30)
            
            // 5. Architectural dependency injection
            Auth(AuthManager.shared)
            Crash(CrashManager.shared)
        }.build()
    }
}
```

Additionally you can simply declare a service wherever you want using the RequestBuilder or initializating a Service struct manually.

```swift
final class ProfileViewModel: ObservableObject {
    var service: Service<MetricsDto, ErrorDto>
    
    init(documentId: String) {
        self.deleteService = DeleteAccreditationsService(id: documentId)
    }
    
    func deleteDocument() async {
        do {
            self.service = RequestBuilder<MetricsDto, ErrorDto> {
                Get(URLs.api, "/metrics/legacy")
                Header(APIConstants.headers)
                
                // Declaratively overrides the standard parser for this instance
                Mapper(legacySerializer)
                
                Auth(AuthManager.shared)
            }.build()

            try await deleteService.service.request()
            print("Operation completed successfully.")
        } catch {
            // Any network anomalies or mapping errors (SerializerError.incorrect) are captured here
            print("Structured error received: \(error)")
        }
    }
}
```


### 2. AuthManager Example

If you want the network layer can manage token renovation by itself passing your AuthManager and it will also add the authHeaders to the calls that use it automatically.

swift
```
actor AuthManager: AuthProtocol {
    static let shared = AuthManager()
    
    private lazy var engine = AuthEngine(onRefresh: Self.refresh)
    
    var authHeader: [String: String] { get async throws { ["Authorization": "Bearer \(try await token.id)"] } }
    var token: Token { get async throws { try await engine.resolveToken() } }
        
    func set(token: Token) async { await engine.set(token: token) }
    
    func invalidate() async { await engine.invalidate() }

    func clear() async { await engine.clear() }
            
    static func refresh() async throws -> Token {
        /*
        Service call to your token refresh service
         */
        return Token(id: "token value", date: .now, expiration: 3600)
    }
}
```

### 3. CrashManager Example

If you want to print or report to lets say Firebase Crashlytics you can pass a CrashManager to the RequestBuilder and you will receive everything thats reported by the library.

swift
```
struct CrashManager: CrashProtocol {
    static let shared = CrashManager()
    
    func report(error: Error, userInfo: [String: Any] = [:]) {
        // let commonInfo: [String: Any] = ["UserID": Defaults.shared.userID].merging(userInfo) { (a, _) in a }
        // Crashlytics.crashlytics().record(error: error, userInfo: commonInfo)
        print("[REPORT] CrashManager: \(error.localizedDescription)\nDetails: \(userInfo)")
    }
}
```
