# Beam

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-007AFF)
![Strict Concurrency](https://img.shields.io/badge/Concurrency-Strict-00B386)
![SPM](https://img.shields.io/badge/SPM-Compatible-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

A networking library for iOS built on Swift Macros. Transforms protocols into type-safe HTTP clients with typed throws, modern concurrency, and full upload/download support with progress tracking and cancellation.

## Features

- **Declarative API definition** — Define endpoints as protocol methods, get a fully implemented client via `@API` macro
- **Typed throws** — Errors are generic over your error DTO, enabling pattern-matching in catch blocks
- **Modern concurrency** — Built on `actor`, `async/await`, `AsyncStream`. No Combine, no completion handlers
- **Strict concurrency compliant** — Compiles clean with `-strict-concurrency=complete`
- **Upload & Download tasks** — Real progress, cancellation, resume data support
- **WebSocket** — Declarative websocket connections with auto-reconnect
- **Byte streaming** — SSE, NDJSON, chunked responses via `ByteStream`
- **Mocking built-in** — No protocols or DI needed. Override any endpoint with a closure
- **Interceptors** — Modify requests/responses transparently (metrics, device headers, auth tokens)
- **Configurable auth** — Token refresh, HMAC signing, static API keys — all composable
- **SSL Pinning** — Certificate pinning via `Client` configuration

## Installation

Add Beam to your project via Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/markos92i/Beam.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repository URL.

## Quick Start

### 1. Define your API

```swift
import Beam

@API(
    host: "https://api.example.com",
    base: "/v2/users",
    headers: ["X-App-Version": "1.0"],
    auth: AuthManager.shared
)
protocol UsersAPI {
    @Get("/{id}")
    func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto

    @Post("")
    func create(body: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto

    @Delete("/{id}")
    func remove(id: Int) async throws(APIError<ErrorDto>)
}
```

The macro generates `UsersAPIClient` with all methods fully implemented.

### 2. Use it

```swift
let user = try await UsersAPIClient().fetch(id: 42)
let newUser = try await UsersAPIClient().create(body: request)
try await UsersAPIClient().remove(id: 42)
```

### 3. Handle errors (typed)

```swift
do {
    let user = try await api.fetch(id: 42)
} catch let error {
    // error.body is typed as ErrorDto? — direct access to server error payload
    showAlert(error.body?.message ?? "Unknown error")
}
```

## Tasks (Progress + Cancellation + Resume)

For operations that need granular control: Live Activity tracking, cancellation with resume data, or binding to views.

```swift
let task = FilesAPIClient().uploadTask(body: .multipart(...)) { progress in
    self.state.progress = progress
}

// Start
try await task.start()

// Cancel with resume data
let resumeData = await task.cancel()

// Resume from where it left off
try await task.start(resumeFrom: resumeData)
```

### Upload task in SwiftUI

Tasks are `Identifiable` — use them as a binding for presentation:

```swift
@State var uploadService: UploadTask<Void, ErrorDto>?

var body: some View {
    content
        .fullScreenCover(item: $uploadService) { task in
            UploadProgressView(state: $state) {
                Task { await task.cancel() }
            }
        }
}
```

## Parameter Detection

The macro infers each parameter's role from its **external label**:

| External label | Role | Example |
|-----------|-----|---------|
| `body` | JSON body | `func create(body request: UserDto)` |
| `query` | Query parameter | `func list(query page: Int)` |
| `header` | Dynamic header | `func get(header token: String)` |
| `url` + type `URL` | Absolute URL override | `func download(url: URL)` |
| Type `[URLQueryItem]` | Direct query items | `func search(params: [URLQueryItem])` |
| Matches `{name}` in path | Path parameter | `@Get("/users/{id}") func get(id: Int)` |
| Type `HTTPBody` | Raw body (multipart, etc) | `func upload(body: HTTPBody)` |

### Escaping collisions

Detection is based on the **external label**. If your domain has a field that collides with a reserved convention, use Swift's dual naming:

```swift
// "body" as HTTP body ✓
func create(body request: CreateRequest) async throws(APIError<E>) -> Item

// Domain field "body" that is NOT the HTTP body — use a different external label:
func update(_ body: BodyModel) async throws(APIError<E>) -> Item
```

## Task Types

```swift
// Data (default) — standard request/response
@Get("/users")
func list() async throws(APIError<ErrorDto>) -> [UserDto]

// Download — returns URL of downloaded file
@Get("/file", task: .download)
func download() async throws(APIError<ErrorDto>) -> URL

// Upload — uploads body with real progress
@Put("/file", task: .upload)
func upload(body: FileDto) async throws(APIError<ErrorDto>)

// Bytes — incremental streaming (SSE, NDJSON, chunked)
@Get("/feed", task: .bytes)
func feed() async throws(APIError<ErrorDto>) -> ByteStream

// WebSocket — bidirectional connection
@Socket("/chat")
func connect() -> WebSocketConnection<Message, ErrorDto>
```

## Streaming (ByteStream)

For endpoints that return data incrementally (SSE, NDJSON, chunked):

```swift
@Post("/completions", task: .bytes)
func complete(body request: CompletionRequest) async throws(APIError<ErrorDto>) -> ByteStream
```

Consume the stream with your preferred format:

```swift
let stream = try await ChatAPIClient().complete(body: request)

// As Server-Sent Events
for try await chunk in stream.sseEvents(CompletionChunk.self) {
    self.text += chunk.delta
}

// As JSON Lines (NDJSON)
for try await chunk in stream.jsonLines(CompletionChunk.self) {
    self.text += chunk.delta
}

// Raw lines
for try await line in stream.lines {
    print(line)
}
```

## WebSocket

```swift
@API(host: "wss://ws.example.com", ...)
protocol ChatAPI {
    @Socket("/chat/{roomId}")
    func connect(roomId: String) async throws(APIError<ErrorDto>) -> WebSocketConnection<ChatMessage, ErrorDto>
}

let connection = try await ChatAPIClient().connect(roomId: "room-42")

for try await event in connection {
    switch event {
    case .message(let msg): handle(msg)
    case .reconnecting(let attempt, _): showReconnecting()
    case .reconnected: hideReconnecting()
    }
}

try await connection.send(ChatMessage(text: "Hello"))
await connection.disconnect()
```

## Authentication

Beam provides three composable auth providers:

### TokenAuth (auto-refresh)

For expiring tokens (Bearer, OAuth2). Handles auto-refresh, deduplication of concurrent refreshes, and token readiness:

```swift
let auth = TokenAuth {
    let response = try await api.refreshToken()
    return .init(value: response.accessToken, expiration: response.expiration)
}

// After login
await auth.set(token: .init(value: jwt, expiration: expiry))

// After logout
await auth.clear()
```

### SignedAuth (HMAC / per-request signing)

```swift
let auth = SignedAuth(name: "HMAC") { request in
    let timestamp = "\(Int(Date.now.timeIntervalSince1970))"
    let signature = HMAC.sign(payload: payload, secret: secret)
    request.addValue(signature, forHTTPHeaderField: "X-Signature")
}
```

### StaticAuth (fixed API keys)

```swift
let auth = StaticAuth(name: "APIKey") { request in
    request.addValue("my-secret-key", forHTTPHeaderField: "X-API-Key")
}
```

## HTTPBody

```swift
let body: HTTPBody = .json(LoginRequest(email: "user@mail.com", password: "secret"))
let body: HTTPBody = .formURLEncoded([URLQueryItem(name: "grant_type", value: "authorization_code")])
let body: HTTPBody = .multipart(MultipartForm(parameters: [...], media: [...]))
let body: HTTPBody = .data(videoData, contentType: .video(format: .mp4))
```

## Per-Route Configuration

```swift
@Get("/critical-data", config: RequestConfig(retry: .resilient, timeout: 120))
func fetchCritical() async throws(APIError<ErrorDto>) -> CriticalDto
```

## Interceptors

```swift
struct MetricsInterceptor: RequestInterceptor {
    func intercept(request: URLRequest) async -> URLRequest {
        var req = request
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        return req
    }

    func didReceive(response: HTTPURLResponse, data: Data, for request: URLRequest) async {
        MetricsService.shared.track(path: request.url?.path() ?? "", status: response.statusCode)
    }
}
```

## Mocking

The generated client includes optional closures for each method — no separate protocols, no flags:

```swift
var api = UsersAPIClient()
api.onFetch = { id in UserDto(id: id, name: "Test") }

let viewModel = UsersViewModel(api: api)
await viewModel.load(userId: 42)
// viewModel.user?.name == "Test"
```

In production, closures are `nil` and the client makes real requests — zero overhead.

## Architecture

```
Beam/
├── Service/       — @API macro support, retry, route builder, task handles
├── Client/        — Actor-based URLSession with progress, cancel, SSL pinning
├── Request/       — APIRequest value type, builder, interceptors, config
├── Auth/          — TokenAuth, SignedAuth, StaticAuth, AuthProtocol
├── HTTP/          — HTTPBody, HTTPMethod, HTTPStatus, MultipartForm, ContentType
├── Error/         — APIError<F>, ClientError, AuthError, SerializerError
├── Serializer/    — JSON encode/decode (Void, String, Data, UIImage support)
└── Support/       — Logger, FileUtils, SSEParser, JSONLinesParser
```

## Requirements

| Requirement | Version |
|------------|---------|
| Swift | 6.3+ |
| iOS | 18.0+ |
| macOS | 15.0+ |
| Xcode | 26+ |

## License

Beam is available under the MIT license. See the [LICENSE](LICENSE) file for details.
