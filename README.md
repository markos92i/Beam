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

## Streaming with `run()`

`run()` returns an `AsyncStream<RunEvent>` that emits progress updates during the operation and a final `.success` or `.failure` event. Unlike `call()`, it doesn't throw — the error arrives as a typed event.

```swift
public enum RunEvent<Success, Failure> {
    case progress(Progress)   // KVO-observable, updates in real time
    case success(Success)     // typed result
    case failure(APIError<Failure>)  // typed error
}
```

### Single operation

```swift
state.type = .loading
for await event in MediaAPI.Upload(url: fileURL).run() {
    switch event {
    case .progress(let p): state.progress = p
    case .success:         state.type = .success
    case .failure:         state.type = .failure
    }
}
```

### With resume data

```swift
let service = MediaAPI.Upload(url: fileURL)
let stream = resumeData != nil ? service.run(resumeFrom: resumeData!) : service.run()

for await event in stream {
    switch event {
    case .progress(let p):         state.progress = p
    case .success:                 state.type = .success
    case .failure(.cancelled):     state.type = .idle
    case .failure(let error):      state.type = .failure
    }
}
```

### Multiple operations in parallel — `.parallel()`

`.parallel()` merges multiple streams into one with a combined `Progress` parent (uses Foundation's `Progress.addChild` for automatic aggregation):

```swift
let streams = [
    CVsAPI.Upload(url: cvFile).run(),
    PhotoAPI.Upload(url: photoFile).run()
]

state.type = .loading
for await event in streams.parallel() {
    switch event {
    case .progress(let p):
        state.progress = p  // combined progress of all operations
    case .success(let results):
        // results[0] = CV result, results[1] = photo result (same order as input)
        state.type = .success
    case .failure(let error):
        // first failure cancels all remaining operations
        state.type = .failure
    }
}
```

### Available `run()` variants

| Task Type | Variants |
|-----------|----------|
| `DataTask` | `run()` |
| `UploadTask` | `run()`, `run(url:)`, `run(resumeFrom:)` |
| `DownloadTask` | `run()`, `run(resumeFrom:)` |

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
Config(RequestConfig(retry: .resilient, pingInterval: 30))
Retry(.exponential(base: 1, maxDelay: 10, maxAttempts: 3))
PingInterval(30)
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

Icons identify the message type at a glance. The protocol (`https`/`http`/`wss`/`ws`) is shown separately with a lock icon for secure connections.

| Icon | Meaning |
|------|---------|
| 􀁶 | Outgoing (request / send) |
| 􀁸 | Incoming (response / receive) |
| 􀀀 | WebSocket open |
| 􀁠 | WebSocket close |
| 􀋧 | HTTP method / WebSocket ping |
| 􁒠 | Headers |
| 􁒡 | Body |
| 􀎠 | Secure (https / wss) |
| 􀎢 | Insecure (http / ws) |

### Request
```
│ 􀁶 A27B    􀋧 GET    􀎠 https    api.example.com/items?page=0
│ 􁒠 [􁠱 auth, 􀡅 json, +3]
```

### Response (success)
```
│ 􀁸 A27B    􀅴 200    􀐫 152ms
│ 􁒠 [􀡅 json, 􀫦 cache, +2]
│ 􁒡
│ {
│   "data" : [
│     { "id" : 1, "title" : "Example Item" }
│   ]
│ }
```

### Response (error)
```
│ 􀁸 7C9E    􀁞 500    􀐫 340ms
│ 􁒠 [􀡅 json, +2]
│ 􁒡
│ {"error":"Internal server error"}
```

### WebSocket
```
│ 􀀀 A27B    􀎠 wss    api.example.com/ws/chat
│ 􁒠 [􁠱 auth, +2]
│ 
│ 􀁶 A27B    text    􀐚 128B
│ 􀁸 A27B    text    􀐚 256B
│ 􀋧 A27B
│ 􀁠 A27B    code: 1000
│ 􀅈 A27B    reconnect 1    delay: 1000ms
```

### Service Error (decode)
```
║
║ 􀇾 Error:    [􀃮 decode]
║ 􀺾 valueNotFound
║     data:
║         items[1]:
║             description: String 􀰌 􀃰 nil
║
```

### Retry
```
│ 􀅈 Retry 1/2 ↓
│ 􀁶 A27B    􀋧 GET    􀎠 https    api.example.com/items?page=0
```

---

## Retry Policy

Retries are configured via `RetryPolicy` inside `RequestConfig`. The same policy applies to both HTTP requests (retry on failure) and WebSocket connections (reconnect on disconnect).

### Presets

| Preset | Behavior |
|--------|----------|
| `.none` | No retries |
| `.standard` (default) | 1 immediate retry |
| `.resilient` | 3 retries with exponential backoff (1s → 2s → 4s, cap 10s) |

### Usage in DSL

```swift
// Default (.standard) — no need to specify anything
struct GetOffers: Endpoint {
    var task: DataTask<[Offer], AppError> {
        Get(host, "/offers")
    }
}

// Resilient preset
struct SubmitApplication: Endpoint {
    var task: DataTask<Confirmation, AppError> {
        Post(host, "/applications")
        Retry(.resilient)
    }
}

// Custom policy
struct CriticalSync: Endpoint {
    var task: DataTask<SyncResult, AppError> {
        Post(host, "/sync")
        Retry(.exponential(base: 2, maxDelay: 60, maxAttempts: 5))
    }
}
```

### Retry behavior

- **401** → invalidates token, retries with refreshed auth
- **5xx / timeout / connection lost** → retries with the configured delay strategy
- **4xx (non-401) / decode errors** → fails immediately, no retry

---

## Error Types

```swift
public enum APIError<Failure> {
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
