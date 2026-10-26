# Beam

![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-007AFF)
![Strict Concurrency](https://img.shields.io/badge/Concurrency-Strict-00B386)
![SPM](https://img.shields.io/badge/SPM-Compatible-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

A networking library for iOS built on Swift macros. `@API` turns a protocol into a type-safe client with typed throws. Data calls, uploads, downloads, background transfers, byte streams and WebSockets share one pipeline: interceptors, auth, retries, validation and monitors.

## Features

- **Declarative routes**: protocol methods with `@Get`, `@Post`…; the compiler checks parameters, placeholders and body types.
- **Typed errors**: `APIError<ErrorDto>` carries the decoded error body.
- **Swift concurrency only**: actors, `async/await`, `AsyncStream`; clean under `-strict-concurrency=complete`.
- **Transfers**: direct calls, cancellable and resumable handles with progress, background transfers that survive the app.
- **Streaming**: SSE and JSON Lines over `ByteStream`; WebSockets with reconnection.
- **Auth**: token refresh, request signing, static keys.
- **Interceptors and monitors**: change requests and responses; observe calls for metrics and crash reports, without credentials.
- **SSL pinning** through the session's trust policy, foreground and background.
- **Mocking**: one closure per route, no protocols or DI.

## Requirements

| Requirement | Version |
|---|---|
| Swift | 6.4+ |
| Xcode | 27+ |
| iOS | 18.0+ |
| macOS | 15.0+ |

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/markos92i/Beam.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** and paste the repository URL.

## Quick start

```swift
import Beam

@API(host: "https://api.example.com", base: "/v2/users", headers: ["X-App-Version": "1.0"], auth: Auth.tokens)
protocol UsersAPI {
    @Get("/{id}")
    func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto

    @Post
    func create(body: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto

    @Delete("/{id}")
    func remove(id: Int) async throws(APIError<ErrorDto>)
}
```

The macro generates `UsersAPIClient`, which implements the protocol:

```swift
let api = UsersAPIClient()
let user = try await api.fetch(id: 42)

do {
    try await api.remove(id: 42)
} catch {
    // error is APIError<ErrorDto>
    guard error != .cancelled else { return }
    showAlert(error.body?.message ?? error.detail)
}
```

## Defining an API

### `@API` arguments

Arguments go in this order:

| Argument | Type | Default | Evaluated |
|---|---|---|---|
| `host` | `String` | required | every request |
| `base` | `String` | `""` | every request |
| `headers` | `[String: String]` | `[:]` | every request |
| `session` | `any SessionProtocol` | `Session()` | once |
| `background` | `Session<Background>?` | `nil` | once |
| `auth` | `(any AuthProtocol)?` | `nil` | once |
| `monitors` | `[any Monitor]` | `[]` | once |
| `config` | `RequestConfig` | `.standard` | once |
| `socket` | `SocketConfig` | `.standard` | once |
| `interceptors` | `[any Interceptor]` | `[]` | once |
| `logLevel` | `LogLevel?` | `nil` (uses `BeamLogger.level`) | once |

"Once" values are built when the API's first client is created, and shared by all its clients. `host`, `base` and `headers` are re-evaluated on every request, so `headers: AppHeaders.current` always reflects the current state (signed-in user, device id…). They run on any thread: keep them cheap and thread-safe. `background:` is described in [Background transfers](#background-transfers), `socket:` in [WebSocket](#websocket). Either one on an API with no routes that use it is a compile warning.

`RequestConfig` holds the defaults every route of the API inherits:

```swift
extension RequestConfig {
    static let app = RequestConfig(
        retry: .resilient,          // default .standard
        timeout: .seconds(20),      // default .seconds(30)
        authPolicy: .required,      // default
        json: .iso8601              // default .default
    )
}
```

### Routes

`@Get`, `@Post`, `@Put`, `@Delete`, `@Patch`, `@Head`, `@Options`, `@Trace` and `@Socket` (a WebSocket, opened with a GET). Arguments go in this order; all are optional and override the API's `config:` for that route:

| Argument | Meaning |
|---|---|
| path | String literal starting with `/`, with `{name}` placeholders |
| `task:` | `.data` (default), `.upload`, `.download`, `.bytes`. Written literally: the macro reads it at compile time. Not on `@Socket` |
| `query:` | Dictionary literal of string literals; a value `"{name}"` is a placeholder |
| `headers:` | Headers for this route |
| `timeout:` | `Duration` |
| `retry:` | `RetryPolicy`; `.none` disables retries |
| `auth:` | `AuthPolicy`: `.required` fails the call when the auth provider fails, `.optional` sends it without credentials |
| `json:` | `JSONCoding`; replaces the API's JSON settings as a whole |

```swift
@Get("/critical", timeout: .seconds(120), retry: .resilient, auth: .optional)
func critical() async throws(APIError<ErrorDto>) -> CriticalDto

@Post("/events", retry: .none)
func track(body: EventDto) async throws(APIError<ErrorDto>)

@Get("/legacy", json: JSONCoding(keyDecoding: .convertFromSnakeCase))
func legacy() async throws(APIError<ErrorDto>) -> LegacyDto
```

The task decides the return type:

| Route | Returns |
|---|---|
| `task: .data` | A decodable type, or nothing (see [Responses and decoding](#responses-and-decoding)) |
| `task: .upload` | Same as `.data`: the response body |
| `task: .download` | `URL` of the downloaded file |
| `task: .bytes` | `ByteStream<Element>` |
| `@Socket` | `WebSocketConnection<Incoming, Outgoing, Failure>` |

The path must be a literal. A path without a leading `/` or with spaces, `<`, `>`, `|`, `\`, `^` or `` ` `` is a warning; string interpolation (`\(…)`) and placeholders that aren't Swift identifiers are errors.

### Retry policies

| Policy | Retries |
|---|---|
| `.none` | none |
| `.standard` (default) | one, immediate |
| `.resilient` | 3, exponential from 1 s, capped at 10 s |
| `.linear(delay:maxAttempts:)` | fixed delay |
| `.exponential(base:maxDelay:maxAttempts:)` | doubling delay, capped |

Only transient failures are retried, and only when repeating them is safe ([RFC 9110 §9.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2)):

| Failure | GET, HEAD, OPTIONS, TRACE, PUT, DELETE | POST, PATCH |
|---|---|---|
| No connection (`notConnectedToInternet`): nothing left the device | Retried | Retried |
| Timeout, lost connection: the server may have applied it | Retried | Not retried |
| `408`, `500`, `502`, `503`, `504`, Cloudflare's `520`–`524` | Retried | Not retried |
| Other statuses (`501`, `505`, `525`…, any other 4xx) | Not retried | Not retried |

POST and PATCH aren't idempotent: repeating one the server already applied would apply it twice. WebSocket handshakes (a GET) that time out are retried too. A `401` is handled by [auth](#authentication), not by the policy.

### Parameter roles

The macro decides each parameter's role from its **external label** only:

| Label | Role | Accepted types |
|---|---|---|
| `body` | Request body | See [Request bodies](#request-bodies-and-content-types) |
| `query name` | Query item keyed by the internal name | `HTTPParameterValue`, raw-value enums, arrays of them, `[URLQueryItem]`; `nil` omits it |
| `header name` | Header keyed by the internal name | `HTTPParameterValue`, raw-value enums; `nil` omits it |
| Matches a `{name}` placeholder (label or internal name) | Fills it | `HTTPParameterValue`, raw-value enums |
| `url` | Absolute URL; in `task: .upload`, the local file to upload | `URL` |
| `resumeFrom` | In upload and download routes, resume data for the direct call | `Data` |
| Anything else, or `_` | Query items | `[URLQueryItem]` or `[URLQueryItem]?`; anything else doesn't compile |

- A label matching a placeholder wins over the `url` role.
- How a value is sent is decided by the compiler from its real type, so typealiases, `Optional<T>`, `T!` and module-qualified names behave like their plain spelling. Unsupported types (a `Date`, a dictionary as a query value, an optional path value) fail to compile with a message explaining why.
- `HTTPParameterValue` covers `String`, `Substring`, `Bool`, all integer types, `Double`, `Float`, `Decimal` and `UUID`; conform your own types to it. `Date` is left out on purpose: its wire format depends on the API, so format it explicitly.
- Headers are layered, later wins: the API's `headers:`, then the route's `headers:`, then `header` parameters.

**Query arrays** repeat the key, as HTML forms do (OpenAPI `style: form, explode: true`). An empty array adds nothing. For another format (`id=1,2`), pass `[URLQueryItem]`:

```swift
@Get("/users")
func users(query id: [Int], query status: Status?, _ extra: [URLQueryItem]) async throws(APIError<ErrorDto>) -> [UserDto]
// api.users(query: [1, 2], query: nil, []) → /users?id=1&id=2
```

**Escaping collisions.** The label decides, so a name that collides with a role takes Swift's dual naming:

```swift
func create(body request: CreateRequest) async throws(APIError<E>) -> Item   // `request` is the HTTP body
func search(query body: String) async throws(APIError<E>) -> [Item]          // query item "body", not the HTTP body
```

### Placeholders and APIValues

Each `{name}` in the path or in a route `query:` value is filled by the parameter `name` or, if there is none, by the `APIValues` property `name`: values shared by every route, declared once in the app as static computed properties.

```swift
extension APIValues {
    static var userID: Int? { UserSession.userID }      // nil when nobody is signed in
    static var locale: String { Locale.current.identifier }
}

@Get("/v2/{userID}/documents/{documentId}", query: ["$expand": "files", "lang": "{locale}"])
func document(documentId: String) async throws(APIError<ErrorDto>) -> DocumentDto
```

- `APIValues` properties are read on every request. The compiler checks that they exist and that their type can be sent.
- A `nil` `APIValues` property fails the request locally with `APIError.missingValue(name)`, before reaching the network.
- Path values can't be optional or arrays. Each one is percent-encoded as a single segment, so a `/` in a value stays escaped.
- In `query:`, a value is a placeholder only when it is exactly `"{name}"`. An optional parameter that is `nil` omits the item.
- `base` plus the route's path, with placeholders unfilled, is the request's `pathTemplate`: it groups error reports and identifies background transfers. That is why paths can't use string interpolation.

### Absolute URLs

A `url: URL` parameter replaces the API's host, base, path and query. Auth, headers, interceptors and retries still apply. Its `pathTemplate` is the route name, `"Protocol.function"` (e.g. `"DocumentsAPI.download"`), which groups its error reports.

```swift
@Get(task: .download)
func download(url: URL) async throws(APIError<ErrorDto>) -> URL
```

WebSocket routes can't take a `url` or a `body`.

### Request bodies and content types

A `body` parameter is sent by its type, the same rule that reads responses:

| Type | Sent as | `Content-Type` |
|---|---|---|
| `Data` | As is | `application/octet-stream` |
| `String` | UTF-8 text | `text/plain; charset=UTF-8` |
| Any other `Encodable & Sendable`, including `Int` and `Bool` | JSON (`5`, `true`), with the route's `JSONCoding` | `application/json; charset=UTF-8` |
| `HTTPBody` | See below | Per case |
| Optional of any of these | No body when `nil` (not `null`) | |

```swift
let body: HTTPBody = .json(LoginRequest(email: "user@example.com", password: "secret"))
let body: HTTPBody = .data(videoData, contentType: .mp4)          // contentType defaults to .data
let body: HTTPBody = .formURLEncoded([URLQueryItem(name: "grant_type", value: "authorization_code")])
let body: HTTPBody = .multipart(MultipartForm(parameters: ["title": "CV"], media: [Media(url: fileURL, key: "file")]))
```

`.formURLEncoded` sends `application/x-www-form-urlencoded` with percent-encoded values. `.multipart` sends `multipart/form-data; boundary=…`; each `Media` is read from its file, with its MIME type taken from the file extension. A `Content-Type` in the route's headers overrides the body's.

**GET, HEAD and TRACE can't send a body or upload**: RFC 9110 gives that content no defined semantics (or forbids it, in TRACE), and URLSession fails or drops it. Declaring one doesn't compile. DELETE and OPTIONS can carry content.

### ContentType

`ContentType` is a struct holding a `Content-Type` or `Accept` value as written. Any string literal is valid; common ones are static members: `.json`, `.text`, `.xml`, `.html`, `.pdf`, `.csv`, `.data`, `.urlEncoded`, `.multipart(boundary:)`, `.png`, `.jpeg`, `.heic`, `.gif`, `.webp`, `.svg`, `.mp4`, `.mov`, `.mp3`, `.m4a`, `.wav`, and the families `.image`, `.video`, `.audio` (`"image/*"`…).

- `==` ignores case and parameter order. Parameter values count, except `charset`, which is case-insensitive.
- In a `switch`, a case matches by media type, ignoring parameters; a family (`.image`, `"*/*"`) matches any type in it. Families also work as an `Accept`.
- `ContentType(url:)` infers it from a file extension, `ContentType(UTType)` from a uniform type; both fall back to `application/octet-stream`.

```swift
switch response.contentType {
case .json?: decodeJSON()
case .image?: showImage()
default: break
}
```

## Responses and decoding

How a body becomes a value is chosen by the compiler from the declared types (the return type, a stream's element, a socket's message, and the `E` of `APIError<E>`):

| Type | Decoded as | `Accept` sent |
|---|---|---|
| `String` | UTF-8 text | `text/plain; charset=UTF-8` |
| `Data` | The raw bytes | `application/octet-stream` |
| Any other `Decodable` | JSON, with the route's `JSONCoding` | `application/json; charset=UTF-8` |
| `Void` (no return type) | Nothing: the body is ignored | none |
| `BodyRepresentable` (e.g. `UIImage`) | Its own decoding | Its `bodyContentType` (`image/*` for `UIImage`) |
| Anything else | Doesn't compile | |

An `Accept` header in the route's headers wins. Downloads aren't decoded (the result is the file), so they send no `Accept` of their own.

Decoding runs off the caller's actor, so a DTO's `Decodable` conformance can't be isolated to one. In a module built with default `MainActor` isolation, mark DTOs `nonisolated` (`nonisolated struct UserDto: Decodable`); the compiler points it out otherwise.

### JSON settings

`JSONCoding` holds the strategies of Apple's `JSONEncoder` and `JSONDecoder` (dates, data, keys, non-conforming floats, output formatting, JSON5, top-level dictionary), with Apple's defaults. `.default` is Apple's; `.iso8601` adds ISO 8601 dates both ways. Set it per API with `RequestConfig(json:)` and replace it per route with `json:`. A fresh encoder and decoder are built for every use, so nothing shared changes while calls run.

```swift
@API(host: "https://api.example.com", config: RequestConfig(json: .iso8601))
protocol UsersAPI {
    @Get("/legacy", json: JSONCoding(keyDecoding: .convertFromSnakeCase))   // no ISO 8601 dates here
    func legacy() async throws(APIError<ErrorDto>) -> LegacyDto
}
```

### Custom formats

A type that isn't `Decodable` can adopt `BodyRepresentable` and be used as a return, error, element or message type. `decodeBody` returns `Self`, so classes such as `UIImage` can adopt it. A type can't be both `Decodable` and `BodyRepresentable`.

```swift
struct PDF: BodyRepresentable {
    let data: Data
    static var bodyContentType: ContentType? { .pdf }

    static func decodeBody(_ data: Data) throws(CodingError) -> PDF {
        guard data.starts(with: Data("%PDF".utf8)) else { throw .typeMismatch }
        return PDF(data: data)
    }
}
```

For a format tied to one call rather than a type, build a `BodyDecoder` and pass it to an [`Endpoint` by hand](#using-endpoint-by-hand):

```swift
extension BodyDecoder where Value == Report {
    static var csv: Self {
        Self(accept: .csv) { (data, _) throws(CodingError) in try Report(csv: data) }
    }
}

let report = try await Endpoint<Report, ErrorDto>(api, request: request, response: .csv, error: .json).data()
```

## Uploads and downloads

### Three ways to run a transfer

Each upload or download route `file(…)` generates:

| Call | Runs on | Cancel |
|---|---|---|
| `file(…)`, `file(…, onProgress:)` | URLSession's native async API | Cancel the calling `Task` |
| `fileTask(…)` → `UploadTask` / `DownloadTask` | The session delegate | `cancel()` from anywhere; returns resume data |
| `fileBackgroundTask(…)` → `BackgroundUploadTask` / `BackgroundDownloadTask` | The background session, while the app is suspended or terminated (requires `@API(background:)`) | `cancel()` |

```swift
@API(host: "https://api.example.com", session: URLSessions.pinned, background: URLSessions.background)
protocol DocumentsAPI {
    @Post("/documents", task: .upload)
    func upload(body: HTTPBody) async throws(APIError<ErrorDto>) -> DocumentDto

    @Get("/documents/{id}/file", task: .download)
    func file(id: String) async throws(APIError<ErrorDto>) -> URL
}

let api = DocumentsAPIClient()
let document = try await api.upload(body: photo)                              // direct
let file = try await api.fileTask(id: "42").start()                           // handle
try await api.uploadBackgroundTask(body: video).start(id: "video-\(videoID)") // background
```

**Upload content.** An upload route uploads either its `body` (encoded in memory, like a [request body](#request-bodies-and-content-types)) or the file at its `url` (streamed from disk). It needs exactly one of them, and the body can't be optional. A file's `Content-Type` isn't inferred: set it with `headers:` or a `header` parameter. A missing or unreadable file fails before sending with `.transport(.file(.readFailed))`, since URLSession would send an empty body. Background uploads write an in-memory body to a temporary file, because background sessions only upload files.

### Progress

`onProgress` receives the call's `Progress` on the main actor before the transfer starts; a handle exposes it as `progress`. Read `fractionCompleted`: units are a fixed scale, not bytes. It is indeterminate while the size is unknown, and restarts on every attempt.

```swift
let file = try await api.file(id: "42", onProgress: { progress in self.progress = progress })

ProgressView(task.progress)   // SwiftUI, with a handle
```

### Handles

- `id` and `progress` exist before the transfer starts. Handles are `Identifiable`, so they work as a presentation item.
- A handle runs one transfer and can start again after it ends. Concurrent starts share its id, progress and cancellation.
- `cancel()` also stops a call waiting before a retry, so no new attempt starts.

```swift
@State private var upload: UploadTask<DocumentDto, ErrorDto>?

content
    .sheet(item: $upload) { task in
        UploadSheet(progress: task.progress) { Task { await task.cancel() } }
    }
```

### Cancellation and resume data

```swift
let task = api.fileTask(id: "42")
do {
    try await task.start()
} catch let error where error == .cancelled {
    // cancelled by the user
} catch {
    resumeData = await task.cancel()   // a failed transfer keeps its resume data
}

try await task.start(resumeFrom: resumeData)   // continues where it left off
```

- `cancel()` returns resume data when URLSession provides it: cancelling a transfer in flight, or after it failed. Uploads only get resume data from servers that support resumable uploads.
- Handles take resume data in `start(resumeFrom:)`, and background downloads in `start(id:resumeFrom:)`. The direct call takes it through a `resumeFrom: Data` parameter of the route.
- URLSession resumes with the request stored in the resume data, and has no API to change it: interceptors and auth can't modify a resumed attempt. If it fails, retries start over with a freshly built request (a `401` refresh re-signs it) and send the upload content again.

> **Resume data is an opaque token.** Apple doesn't document its format, and Beam doesn't inspect it. Pass only what URLSession produced (`cancel()`, or the error of an interrupted transfer), unchanged. Data URLSession can't read fails the call with `URLError.unsupportedURL`, but a download resumed from a property list URLSession didn't write (even `Data("resume".utf8)`) can end the process: URLSession raises an Objective-C exception, which Swift can't catch.

### Where downloads go

A download returns `Caches/<unique folder>/<name>`, where the name is the one the server suggests (with an extension from its `Content-Type` when missing). Each download gets its own folder, so two with the same name don't replace each other. The system may purge Caches when space runs low: move the file to keep it. A download that fails (error status, interceptor, retry, storage) leaves no file.

## Background transfers

A transfer that must survive the user leaving the app runs on a background session. Create it once per identifier, for the whole process (see [Sessions](#sessions-and-ssl-pinning)), and pass it as `@API(background:)`:

```swift
enum URLSessions {
    static let pinned = Session(trustPolicy: CertificatePinning.app)
    static let background = Session(.background("com.myapp.transfers"), trustPolicy: CertificatePinning.app)
}
```

- `<route>BackgroundTask(…)` exists only for upload and download routes of an `@API` with `background:`. `start(id:)` requires an id.
- **The id identifies the transfer** on its route. Starting again with an id in flight attaches to that transfer (its progress and result) instead of transferring twice. That covers a double tap, and coming back to a screen after the app was killed mid-upload. If it already finished with nobody awaiting it, the new start takes that result. Use an id that identifies the content (a document id, a file hash), not the screen.
- While the app is alive, the `await` of `start(id:)` gets the full typed result, through the route's interceptors, decoding, retries and monitors.

### Results after a relaunch

Transfers that finished with nobody awaiting them come out of `finished(until:)` on the background session, stored ones first (oldest first), then new ones as they arrive. Each `FinishedTransfer` is validated (a non-2xx status is `.failed(.http(…))`) but skips the route's interceptors and decoding, is never retried, and monitors never see it.

```swift
// App scene: handle every result
.backgroundTask(.urlSession(URLSessions.background.identifier)) {
    let session = URLSessions.background
    for await transfer in session.finished(until: .eventsDelivered) {
        switch transfer.outcome {                    // also transfer.id, .method, .pathTemplate, .response
        case .uploaded:
            save(try? transfer.decode(DocumentDto.self, json: .iso8601))
        case .downloaded(let file):
            try? FileManager.default.moveItem(at: file, to: destination)   // move it before removing
        case .failed(let error):                     // APIError<Void>
            report(error)
        }
        session.remove(transfer)
    }
}

// A screen: only its own transfer, until the view goes away
.task {
    for await transfer in URLSessions.background.finished() where transfer.id == document.id { … }
}
```

- `until: .eventsDelivered` ends the stream when iOS has delivered the events it relaunched the app for, as `.backgroundTask(.urlSession(…))` needs. The default, `.cancelled`, ends it when the iterating task is cancelled.
- Several listeners can run at once; each gets every result. Filter by `FinishedTransfer.id`.
- `finished` doesn't remove anything: each result stays on disk until `remove(_:)`, or until a `start(id:)` with the same id and route takes it. Remove each one once handled. A finished download stays in Beam's store (Application Support, excluded from backup), so move it first.
- `body` holds the response body of an upload, including the error message of a failed one, or the error body of a rejected download.
- `decode(_:json:)` reads `body` as JSON and `decode(using:json:)` with any `BodyDecoder`. Pass the API's JSON settings: route settings don't survive a relaunch. They throw `CodingError`: `.typeMismatch` when there is no body, `.decoding` when it doesn't decode.
- `remove(_:)` does nothing for a result that wasn't kept. `removeAllFinishedTransfers()` removes every result and its file, e.g. on logout.

## Streaming (ByteStream)

Declare a `task: .bytes` route returning `ByteStream<Element>`; elements decode like any body (see [Responses and decoding](#responses-and-decoding)), with the route's JSON settings.

```swift
@Post("/completions", task: .bytes)
func complete(body request: CompletionRequest) async throws(APIError<ErrorDto>) -> ByteStream<CompletionChunk>
```

| Read | Yields |
|---|---|
| `sseEvents()` | Each Server-Sent Event's data decoded as `Element`; events without data are skipped |
| `sseRawEvents()` | `SSEvent` undecoded: `event`, `data`, `id`, `retry` |
| `jsonLines()` | Each non-empty line decoded as `Element` (NDJSON) |
| `lines` / `allLines` | Text lines; `allLines` keeps the empty ones |
| `bytes` | The raw `URLSession.AsyncBytes`, with URLSession's untyped errors |

Opening the stream is a call like any other (interceptors, auth, retries, monitors), and its status is validated before the stream is returned. So iterating fails with `APIError<Never>`: `.cancelled` after `stream.cancel()`, `.transport` when the connection drops, and `.coding` when an element can't be decoded. Decoding failures are logged; monitors don't see them, because the call already succeeded.

```swift
let stream = try await CompletionsAPIClient().complete(body: request)
do {
    for try await chunk in stream.sseEvents() { text += chunk.delta }
} catch {
    guard error != .cancelled else { return }
    show(error)
}
```

## WebSocket

```swift
extension SocketConfig {
    static let chat = SocketConfig(ping: .seconds(20), maxMessageSize: 4_000_000)
}

@API(host: "wss://ws.example.com", socket: .chat)
protocol ChatAPI {
    @Socket("/rooms/{roomId}")
    func join(roomId: String) async throws(APIError<ErrorDto>) -> WebSocketConnection<ChatEvent, ChatCommand, ErrorDto>
}

let connection = try await ChatAPIClient().join(roomId: "42")

// Consume messages and state in separate tasks.
Task {
    do {
        for try await event in connection.messages { handle(event) }
    } catch {
        show(error)   // APIError<ErrorDto>: why the connection ended
    }
}
Task {
    for await state in connection.state {
        switch state {
        case .reconnecting(let attempt, let max): banner = "Reconnecting \(attempt)/\(max)"
        case .connected: banner = nil
        case .disconnected: break
        }
    }
}

try await connection.send(.say("Hello"))   // a ChatCommand
await connection.disconnect()
```

- **Types.** The connection receives `Incoming` and sends `Outgoing`, each read and written by its type like any body: `Decodable`/`Encodable` as JSON, `String` as text, `Data` as is. `send(_:)` exists only when `Outgoing` can be encoded; `send(data:)` and `send(text:)` always exist. JSON goes in text frames unless `jsonFrames: .binary`.
- **Handshake.** `join(…)` goes through the API's interceptors, auth (a `401` refreshes once), validation, `retry` and monitors, and returns once connected (`101`). An upgrade the server refuses is `.http(status:…)`.
- **Lifetime.** The connection stays open while something holds it or its `messages`; releasing them, stopping the iteration or `disconnect()` closes it.
- **Messages.** A message that can't be decoded is skipped and logged at `.error`; the connection goes on, and monitors don't see it. One bigger than `maxMessageSize` ends the connection with `.connection(.messageTooLarge)`.
- **Sending** while reconnecting, or after the end, fails at once with `.connection(.notConnected)`; nothing is queued.
- **State** drives the UI; only the latest is buffered. It starts at `.connected`; `.reconnecting(attempt:maxAttempts:)` announces each reconnection attempt and `.disconnected(reason:)` the end: `.closed` (the server closed with 1000), `.intentional` (`disconnect()` or the connection was released), or `.error(kind)`.

### Reconnection

When an open connection drops, Beam re-establishes it with `SocketConfig.reconnect` (`.resilient` by default) and the new connection's messages keep coming in the same `messages`. Whether it reconnects depends on how it ended:

| Ending | What happens |
|---|---|
| Close 1000 | `messages` ends without an error |
| Close 1001, 1006, 1011, 1012, 1013, 1014; lost network; no pong in time | Reconnects |
| Close 1002, 1003, 1007–1010; message over the limit | Ends with `.connection(…)`, not retried |
| Close 4000–4999 (application codes) | Ends, unless listed in `reconnectsOn` |

The reconnection budget starts over once a connection delivered a message or lasted the handshake `timeout`; a server that accepts and closes at once runs out of attempts. Reconnecting when the app returns to the foreground or the network comes back is up to the app (`scenePhase`, `NWPathMonitor`): connect again.

### `SocketConfig`

`@API(socket:)` sets it for the API's sockets; the same options on `@Socket` override it per route. They don't exist on other routes, so they can't be set where they wouldn't apply.

| Option | Default | |
|---|---|---|
| `ping` | `nil` | Keep-alive interval, 1–300 s; a literal out of range doesn't compile |
| `pongTimeout` | `ping` | Without a pong in this time, the connection counts as dropped |
| `maxMessageSize` | 1 MB | Largest message received |
| `reconnect` | `.resilient` | Policy after a drop; `retry` covers the first connection |
| `protocols` | `[]` | Subprotocols offered; `connection.protocol` is the one the server chose |
| `jsonFrames` | `.text` | `.text` or `.binary` |
| `reconnectsOn` | `[]` | Application close codes (4000–4999) that reconnect |

```swift
@Socket("/graphql", protocols: ["graphql-transport-ws"], ping: .seconds(10), reconnect: .exponential(base: .seconds(1), maxDelay: .seconds(30), maxAttempts: 10))
func subscriptions() async throws(APIError<ErrorDto>) -> WebSocketConnection<GraphQLMessage, GraphQLMessage, ErrorDto>
```

## Sessions and SSL pinning

Beam owns each session's delegate, through which trust evaluation, delegate-driven transfers and background events go. The mode, the first argument, decides whether the session is foreground or background:

```swift
Session()                                                   // .default: Session<Foreground>
Session(trustPolicy: CertificatePinning.app)                // SSL pinning
Session(.ephemeral) { $0.waitsForConnectivity = true }      // nothing persisted to disk
Session(.background("com.myapp.transfers"), trustPolicy: CertificatePinning.app) {   // Session<Background>
    $0.allowsCellularAccess = false
}
```

- `configure` gets the real `URLSessionConfiguration`: cache, cookies, connectivity, cellular access, shared container… Request timeouts and headers belong to `@API` and the routes, not to the session.
- A `Session<Foreground>` goes in `@API(session:)`; a `Session<Background>` only in `@API(background:)`. So data calls, byte streams and WebSockets never reach a background session, which can't run them.
- Create **one background session per identifier**, in a `static let`: two sessions with the same identifier are undefined behaviour, and releasing a session cancels its transfers. Use the same identifier on every launch to reconnect with the previous launch's transfers.
- `allTasks` lists the session's tasks; `cancelAllTasks()` cancels them.

A `TransportTrustPolicy` evaluates every server trust challenge of the session. A server it rejects fails with kind `.sslError`, not as a cancellation:

```swift
struct CertificatePinning: TransportTrustPolicy {
    static let app = CertificatePinning(certificates: [pinnedDER])
    let certificates: Set<Data>   // DER data of the accepted certificates

    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
        guard SecTrustEvaluateWithError(trust, nil),
              chain.contains(where: { certificates.contains(SecCertificateCopyData($0) as Data) }) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
```

## Authentication

Auth signs each attempt after the API's interceptors, so a signature sees the final request. When an API with an auth provider gets a `401`, Beam calls `invalidate()` and repeats the call once; that repeat doesn't count against the `RetryPolicy` (monitors see it as `willRetry` with zero delay). Without a provider, a `401` is a plain `.http(status: .unauthorized)`. Providers log with the global `BeamLogger.level`, since several APIs share them.

### TokenAuth

For expiring tokens. It refreshes an expired token before use and after `invalidate()`, shares one refresh among concurrent calls, and makes requests wait until the app sets the first token or clears it. It sends `Authorization: Bearer <token>`, or what `apply:` sets.

```swift
enum Auth {
    static let tokens = TokenAuth(
        refresh: { () async throws(AuthError) -> TokenAuth.Token in
            do throws(APIError<ErrorDto>) {
                let session = try await SessionAPIClient().refresh(body: RefreshRequest(token: Keychain.refreshToken))
                return TokenAuth.Token(value: session.accessToken, expiresIn: session.expiresIn)
            } catch where error.status == .unauthorized {
                throw .invalidCredentials
            } catch {
                throw .failedToRefreshToken
            }
        },
        onSessionLost: { await AppRouter.shared.showLogin() }
    )
}

await Auth.tokens.set(token: .init(value: jwt, expiration: expiry))   // after login
await Auth.tokens.clear()                                             // on logout: later calls fail with .missingToken
```

- `onSessionLost` runs when `refresh` throws `.invalidCredentials`; the token is cleared first. Use it to go to the login screen, without network calls.
- Any other refresh error is `.failedToRefreshToken` (kind `.tokenExpired`), and the next call tries to refresh again.
- Call the refresh endpoint through an API that doesn't use the same provider: a call waiting for the refresh it belongs to never finishes.

### SignedAuth and StaticAuth

```swift
let signed = SignedAuth(name: "HMAC") { (request: inout URLRequest) async throws(AuthError) in
    guard let secret = Keychain.signingSecret else { throw .missingToken }
    request.setValue(HMAC.signature(of: request, secret: secret), forHTTPHeaderField: "X-Signature")
}

let apiKey = StaticAuth(name: "APIKey") { request in
    request.setValue(Secrets.apiKey, forHTTPHeaderField: "X-API-Key")
}
```

Their credentials can't be refreshed: after a `401` the repeat is sent the same way, a second `401` surfaces as `.http(status: .unauthorized)`, and the provider stays usable.

## Interceptors

An interceptor changes the request before each attempt and the response after it, or rejects the call: add headers or signatures, reject a `200` that carries an error envelope, unwrap envelopes. Retries belong to `RetryPolicy` and observing to [monitors](#monitors-and-crash-reports). Both methods have pass-through defaults.

```swift
struct EnvelopeInterceptor: Interceptor {
    func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        var request = request
        request.setValue(Device.id, forHTTPHeaderField: "X-Device")
        return request
    }

    func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response {
        guard case .data(let data) = response.body else { return response }
        if let error = Envelope.error(in: data) {
            throw .rejected(status: .unprocessableEntity, body: error)   // the server answered 200 with {"error": …}
        }
        return Response(http: response.http, body: .data(Envelope.payload(of: data)))
    }
}
```

Interceptors run in order on every attempt. Auth signs after their request hook, and status validation runs after their response hook, so they see every response, including non-2xx ones. `EndpointContext` carries the call id, method, path template, operation, attempt number, previous attempts and elapsed time.

| `InterceptorError` | Surfaces as |
|---|---|
| `auth(AuthError)` | `APIError.auth` |
| `rejected(status:body:)` | `APIError.http`, with `body` decoded into the route's `Failure` |
| `custom(any Error)` | `APIError.intercepted`, with the original error (`.cancelled` for a `CancellationError`) |

Built in: `RequestIDInterceptor(headerName: "X-Request-ID")` adds a UUID per attempt; `DynamicHeadersInterceptor { await … }` adds headers resolved at request time.

## Monitors and crash reports

A monitor observes every call of its API without changing it: hooks are synchronous, can't throw, and have empty defaults. Requests given to monitors never carry `Authorization`, `Proxy-Authorization`, cookies or headers whose name contains `token` or `secret`; other credential headers (e.g. `X-API-Key`) do reach them.

| Hook | When |
|---|---|
| `didSend` | An attempt is about to be sent, after interceptors and auth |
| `didReceive` | An attempt received a response, before interceptors and validation |
| `willRetry(after:delay:)` | The call failed and will be repeated |
| `didSucceed` | The call succeeded |
| `didFail` | The call failed for good |

```swift
struct CrashReporter: Monitor {
    func didFail(_ failure: EndpointFailure, context: EndpointContext) {
        guard !failure.isExpected else { return }   // cancelled, offline, timed out
        let report = failure.report(including: [.responseBody, .requestBody(redacting: ["password"])])
        Crashlytics.crashlytics().record(error: report.error, userInfo: report.info)
    }
}

let metrics = ClosureMonitor(didSucceed: { response, context in Metrics.record(context.pathTemplate, context.elapsed) })
```

- `EndpointFailure` has the final `error` (`APIError<Void>`), the last `request` (`nil` if the call failed before sending) and the last `response`.
- A report's `domain` is `"METHOD /template — errorName"` and its `code` the error's `id`, so occurrences group together. `info` holds the concrete `Method`, `Host`, `Path`, `Attempt`, `ErrorDetail` and, when a response arrived, its numeric `Status`.
- Bodies are opt-in and may contain personal data. Only text bodies are added, truncated to 1 kB per value (Crashlytics' limit). Redacted JSON values, at any depth, become `"•••"`.
- Beam always installs its own log monitor, which logs retries and final errors.

## Errors

Every call throws `APIError<Failure>`, where `Failure` is the route's decoded error body:

| Case | Meaning |
|---|---|
| `invalidURL` | The URL couldn't be built from host and path |
| `missingValue(name)` | An `APIValues` property was `nil`, typically because nobody is signed in |
| `conflictingUploadData` | An upload's request has a body of its own |
| `cancelled` | Any cancellation: task, URLSession, auth or socket |
| `http(status:body:response:)` | A non-2xx response |
| `transport(TransportError)` | `network(URLError)`, or `file(FileError)`: a file the transfer needs |
| `connection(WebSocketError)` | `closed(code:reason:)`, `unexpectedDisconnection`, `pingFailed`, `messageTooLarge`, `notConnected`, `network`, `sendFailed` |
| `auth(AuthError)` | `missingToken`, `invalidCredentials`, `failedToRefreshToken` |
| `coding(CodingError)` | `encoding`, `decoding` (with the coding path), `typeMismatch` (the body isn't the text, image or data the call reads) |
| `storage(FileError)` | A file of the call itself: a multipart file, moving a finished download to Caches |
| `intercepted(any Error)` | An interceptor's own error |

`FileError` is `readFailed`, `writeFailed`, `moveFailed` or `copyFailed`, with the `CocoaError` and its path. Its kind is `.storage` whether it arrives as `.transport(.file(…))` or `.storage(…)`.

`APIError` is not `Equatable` on purpose: errors carry bodies and underlying errors that don't compare meaningfully. Compare by kind instead, `APIErrorKind`, a flat vocabulary without payloads (`noConnection`, `timedOut`, `serverUnreachable`, `sslError`, `http(status:)`, `storage`…):

```swift
guard error != .cancelled else { return }
if error == .http(status: .notFound) { … }
switch error.kind {
case .noConnection: showOffline()
case .http(let status): show(status.name)   // reason phrase, e.g. "Not Found"
default: break
}
```

Reach the details with pattern matching. `.http` has three values, so patterns need three elements:

```swift
if case .transport(.network(let urlError)) = error, urlError.code == .timedOut { … }
if case .coding(.decoding(_, let description)) = error { print(description) }

if case .http(status: .badRequest, let body, _) = error, body.value == nil {
    showAlert(body.text ?? "")        // another error format: try another type with body.data
}

if case .http(_, let body, let response?) = error, let page = body.data, let url = response.url {
    webView.load(page, mimeType: response.mimeType ?? "text/html",
                 characterEncodingName: response.textEncodingName ?? "utf-8", baseURL: url)
}
```

- `HTTPErrorBody` keeps the body as sent (`data`, whole in data calls, up to 64 KB for downloads and streams) and its decoded `value`. When the body doesn't decode as `Failure`, `value` is `nil`, `decodingError` says why, and Beam logs a warning. `text` reads `data` as UTF-8.
- Shortcuts: `error.status`, `error.body` (the decoded value), `error.rawBody`, `error.response`, `error.detail`.
- `error.response` is the server's response (final URL, headers, `Content-Type`). It is `nil` only when a request interceptor rejected the call before sending it.
- A status Beam doesn't know is `.undefined` (`http(0)`); the report's `Status` keeps the real number.
- `isExpected` is `true` for cancelled, offline and timed out: not worth reporting. `id` and `name` are stable per kind, for crash report grouping.
- `asVoid` converts to `APIError<Void>`, dropping the decoded body and keeping the raw one.

## Logging

Beam logs to the unified log (`os.Logger`, subsystem `com.beam`):

| | Debug | Release |
|---|---|---|
| `BeamLogger.level` | `.debug` | `.warning` |
| Message privacy | `.public` | `.private`: `<private>` without a logging profile |

- `level` can change at runtime; privacy can't.
- Bodies are logged at `.debug`, whole (JSON pretty-printed). Above it a body shows only its size, except an error response (status ≥ 400), which always shows its own.
- `@API(logLevel:)` sets the minimum level of everything an API's calls log. APIs without it use `BeamLogger.level`, and so do auth providers and background sessions (including transfers nobody awaits). `BeamLogger.level = .off` silences every Beam log, including APIs with their own `logLevel`.
- `.warning` and `.error` reach the unified log as `OSLogType.error`; Beam never logs `.fault`.
- The first line of each entry is aligned in columns, so a request lines up with its response.
- `request.curl` renders a `URLRequest` as a copy-pasteable cURL command (`po request.curl` in LLDB).

| Level | Logged |
|---|---|
| `.debug` | WebSocket messages and pings, credentials rejected by `SignedAuth` or `StaticAuth` |
| `.info` | Requests, responses, retries, WebSocket open and close, `TokenAuth` state, finished background results |
| `.warning` | 5xx responses, WebSocket reconnections, error bodies that don't decode, failed background results |
| `.error` | Final errors, stream elements and WebSocket messages that don't decode, WebSocket messages that don't encode |

## Mocking and testing

The generated client has an optional closure per route. In production they are `nil` and the client makes real requests:

```swift
var api = UsersAPIClient()
api.onFetch = { id in UserDto(id: id, name: "Test") }

let viewModel = UsersViewModel(api: api)
await viewModel.load(userId: 42)   // viewModel.user?.name == "Test"
```

- Closures are named `on<Name>`. Overloaded routes add the first parameter's label: `onItemId` and `onItemCode` for `item(id:)` and `item(code:)`, with a number when that still collides.
- A closure receives the route's parameters and skips interceptors, auth and monitors.
- Data, upload, download and WebSocket routes are mockable. One closure answers every way of calling the route: the direct call, `<route>Task(…)` and `<route>BackgroundTask(…)`. If the route has a `resumeFrom` parameter, the closure gets the resume data passed to `start(resumeFrom:)`, or empty data without it.
- A mocked call is cancelled like a real one: `cancel()` or cancelling the calling task makes it throw `.cancelled`.
- WebSocket routes answer with `WebSocketConnection.mock(_:failure:protocol:onSend:)`: it yields the given messages, stays open until `disconnect()` (or ends with `failure`), and hands what the app sends to `onSend`:
  ```swift
  api.onJoin = { roomId in .mock([.joined(roomId)]) { command in sent.append(command) } }
  ```
- Byte stream routes have no closure: a test can't build a `ByteStream`. Inject a session instead with `UsersAPIClient(session:)`, which also serves tests and previews of any route.

## Using Endpoint by hand

`@API` generates calls to `Endpoint`, which can also be used directly. `APIConfiguration` takes the same arguments as `@API`, and builds requests:

```swift
let api = APIConfiguration(host: "https://api.example.com", auth: Auth.tokens, config: .app)

let request = api.request(.get, "/users/{id}", values: ["id": "42"], query: [URLQueryItem(name: "expand", value: "teams")])
let user = try await Endpoint<UserDto, ErrorDto>(api, request: request).data()

let file = try await Endpoint<URL, ErrorDto>(api, request: api.request(.get, url: fileURL, route: "Files.download")).download()
```

- `request(_:_:values:query:headers:body:)` fills placeholders from `values`; a placeholder without a value is sent as written. `headers:`, when given, replaces the API's headers. `request(_:url:route:headers:body:)` targets an absolute URL; `route` names it in error reports. `APIRequest.pathTemplate` defaults to its `path`.
- The `Success` and `Failure` types pick the decoding as in [Responses and decoding](#responses-and-decoding); an unsupported type doesn't compile. Pass `response:` and `error:` decoders for a custom format, and `config:` to replace the API's `RequestConfig`.
- An `Endpoint` is stateless: it can be called many times, concurrently. Each call has its own id, progress and cancellation.

| Method | Does |
|---|---|
| `data()` | A data call |
| `upload(_:resumeFrom:onProgress:)`, `download(resumeFrom:onProgress:)` | Native async transfers, cancelled with the calling task; `resumeFrom` applies to the first attempt |
| `uploadTask(_:)`, `downloadTask()` | Handles |
| `backgroundUploadTask(on:_:)`, `backgroundDownloadTask(on:)` | Background handles |
| `stream()`, `connect(socket:)` | Byte stream and WebSocket |
| `mocking(_:)` | The same endpoint answered by a mock; `nil` restores the network |

`download` and the download handles exist on `Endpoint<URL, Failure>` and return the file. Uploads take an `UploadContent`: `.body(HTTPBody)` encoded in memory (e.g. `.body(.multipart(form))`), or `.file(URL)` streamed from disk. Upload requests carry no body of their own: one fails with `APIError.conflictingUploadData`.

```swift
let endpoint = Endpoint<UserDto, ErrorDto>(api, request: request)
    .mocking(.init { resume in UserDto(id: 42, name: "Test") })   // resume: the call's resume data, if any
```

## Architecture

```
Beam/
├── Macro/         @API and route macros, parameter helpers, APIConfiguration
├── Endpoint/      Endpoint and Call: request building, interceptors, auth, retries, validation, monitors
├── Transport/     Client, Session (foreground and background), SessionDelegate, finished transfers, trust policy
├── Handle/        UploadTask, DownloadTask, BackgroundUploadTask, BackgroundDownloadTask
├── WebSocket/     Socket, WebSocketConnection, handshake, connection state
├── Stream/        ByteStream, ThrowingStream, SSE and JSON Lines parsing
├── Interceptor/   Interceptor, InterceptorError, EndpointContext, built-in interceptors
├── Monitor/       Monitor, EndpointFailure, ErrorReport, ClosureMonitor
├── Auth/          AuthProtocol, TokenAuth, SignedAuth, StaticAuth
├── Request/       APIRequest, APIValues, HTTPBody, MultipartForm, UploadContent
├── Model/         HTTPMethod, HTTPStatus, ContentType, RequestConfig, RetryPolicy, AuthPolicy
├── Coding/        JSONCoding, BodyDecoder, BodyRepresentable
├── Error/         APIError, APIErrorKind, HTTPErrorBody and the layer errors
├── Logging/       BeamLogger and log formatting
├── Extensions/    URLRequest.curl
└── Support/       File handling
```

## License

Beam is available under the MIT license.
