# NetworkActor

A declarative, type-safe networking layer for Swift built with `@resultBuilder`. Compile-time validation, typed endpoints, structured error handling, and beautiful console logging.

---

## Defining Endpoints

Endpoints conform to `Endpoint` and declare their operation type via `DataTask`, `UploadTask`, or `DownloadTask`:

```swift
enum API {
    struct Search: Endpoint {
        let page: Int

        var task: DataTask<[ItemDto], AppError> {
            Get(AppConfig.baseURL, "/items")
            Query("page", value: "\(page)")
            Header(AppConfig.headers)
            Use(Client(certificates: AppConfig.certificates))
            Auth(AuthManager.shared)
            Crash(CrashManager.shared)
        }
    }

    struct Download: Endpoint {
        let code: String

        var task: DownloadTask<AppError> {
            Get(AppConfig.baseURL, "/documents/\(code)")
            Header(AppConfig.headers)
            Auth(AuthManager.shared)
            Crash(CrashManager.shared)
        }
    }
}

enum MediaAPI {
    struct Upload: Endpoint {
        let url: URL

        var task: UploadTask<Void, AppError> {
            Put(AppConfig.baseURL, "/media/upload")
            Body(.multipart(.init(media: [.init(url: url, key: "file")])))
            Auth(AuthManager.shared)
            Crash(CrashManager.shared)
        }
    }
}
```

---

## Calling Endpoints

All endpoints use `.call()` — the task type determines the underlying operation:

```swift
// Data request
let offers = try await API.Search(page: 0).call()

// Download
let file = try await API.Download(code: "ABC").call()

// Upload with progress
let task = MediaAPI.Upload(url: fileURL)
for await progress in task.progress { updateUI(progress) }
try await task.call()

// Cancel
await task.cancel()
```

---

## Task Types

| Type | Operation | Return |
|------|-----------|--------|
| `DataTask<Success, Failure>` | `URLSession.data` | Decoded `Success` |
| `UploadTask<Success, Failure>` | `URLSession.upload` | Decoded `Success` |
| `DownloadTask<Failure>` | `URLSession.download` | `URL` to file |

The compiler enforces that you can only call `.call()` — you cannot accidentally call upload on a DataTask or download on an UploadTask.

---

## DSL Components

```swift
// HTTP Methods (first line, mandatory)
Get(host, path)
Post(host, path)
Put(host, path)
Delete(host, path)
Patch(host, path)

// Request modifiers
Header("Key", value: "Value")
Header(["Key1": "Value1", "Key2": "Value2"])
Query("name", value: "value")
Query([URLQueryItem(name: "a", value: "1")])
Body(.json(encodable))
Body(.data(rawData))
Body(.multipart(form))
Timeout(30)

// Infrastructure
Use(Client(session:, certificates:, crash:))
Auth(authManager)
Crash(crashManager)
Config(ServiceConfig(maxRetries: 2))
```

---

## Auth Manager

The library handles token refresh automatically. Implement `AuthProtocol`:

```swift
actor AuthManager: AuthProtocol {
    static let shared = AuthManager()

    private lazy var engine = AuthEngine(onRefresh: Self.refresh)

    var authHeader: [String: String] {
        get async throws { ["Authorization": "Bearer \(try await token.id)"] }
    }

    var token: Token { get async throws { try await engine.resolveToken() } }

    func set(token: Token) async { await engine.set(token: token) }
    func invalidate() async { await engine.invalidate() }
    func clear() async { await engine.clear() }

    static func refresh() async throws -> Token {
        let response = try await AuthService.Refresh().call()
        return Token(id: response.accessToken, date: .now, expiration: response.expiresIn)
    }
}
```

`AuthEngine` handles concurrency: multiple simultaneous 401s trigger a single refresh, and all waiting requests resume with the new token.

---

## Crash & Log Protocol

Implement `CrashProtocol` to receive error reports and formatted logs:

```swift
struct CrashManager: CrashProtocol {
    static let shared = CrashManager()

    func report(error: Error, userInfo: [String: Any]) {
        YourCrashService.record(error: error, userInfo: userInfo)
    }

    func log(_ output: String) {
        #if DEBUG
        print(output)
        #endif
    }
}
```

Disable request/response logs at any time:
```swift
Logger.enabled = false
```

---

## Console Output

### Request
```
│ 􀁶 Request: A27B    􀋧 GET    􀎠 https://api.example.com/items?page=0
│ 􁒠 Header: [􁠱 auth, 􀡅 json, 􀠩, 􀠩, 􀠩]
```

### Response (success)
```
│ 􀁸 Response: A27B    􀅴 200    􀐫 152ms
│ 􁒠 Header: [􀡅 json, 􀫦 cache, 􀠩, 􀠩, 􀠩]
│ 􁒡 Body:
│ {
│   "data" : [
│     { "id" : 1, "title" : "Example Item" }
│   ]
│ }
```

### Response (error)
```
│ 􀁸 Response: 7C9E    􀁞 500    􀐫 340ms
│ 􁒠 Header: [􀡅 json, 􀠩, 􀠩]
│ 􁒡 Body:
│ {"error":"Internal server error"}
```

### Service Error (decode)
```
║
║ 􀇾 Error:    [􀙄 decode]
║ 􀺾 valueNotFound
║     data:
║         items[1]:
║             description: String 􀰌 􀃰 nil
║
```

### Retry
```
│ ↻ Retry 1/2
│ 􀁶 Request: A27B    􀋧 GET    ...
```

---

## Retry Policy

Retries are automatic for transient errors (5xx, timeout, connection lost, 401):

```swift
Config(ServiceConfig(maxRetries: 2))
```

- **401** → invalidates token, retries with refreshed auth
- **5xx / timeout / noConnection** → retries with exponential backoff (200ms, 400ms...)
- **4xx (non-401) / decode errors** → fails immediately, no retry

---

## Error Types

```swift
public enum ServiceError<Failure> {
    // Serialization
    case encode, decode, unsupportedType, typeMismatch

    // Request
    case invalidURL, invalidFormat, missingUploadData, missingToken, tokenExpired

    // Network
    case noConnection, timedOut, serverUnreachable, sslError, noResponse

    // Server
    case http(status: HTTPStatus, body: Failure?)

    // System
    case storage, cancelled, unknown
}
```

Each error has a unique icon for console identification and is reported to Firebase with a sanitized path:
```
GET /api/{id}/settings — decode (1)
```

---

## SSL Pinning

Pass certificates to the Client. If `certificates` is empty, pinning is disabled:

```swift
Use(Client(certificates: [myCertData]))  // pinning enabled
Use(Client())                            // no pinning
```

---

## Requirements

- iOS 18.0+
- Swift 6 (strict concurrency)
- Xcode 26+
