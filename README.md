# Beam

Librería de networking para iOS basada en macros Swift. Transforma protocolos en clientes HTTP type-safe con typed throws, concurrencia moderna, y soporte completo para uploads/downloads con progreso y cancelación.

## Definir una API

```swift
import Beam

@API(
    host: "https://api.example.com",
    base: "/v2/users",
    headers: ["X-App-Version": "1.0"],
    client: Client(session: .shared, certificates: []),
    auth: AuthManager.shared,
    crash: CrashManager.shared
)
protocol UsersAPI {
    @Get("/{id}")
    func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto

    @Post("")
    func create(body: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto

    @Put("/{id}")
    func update(id: Int, body: UpdateUserRequest) async throws(APIError<ErrorDto>)

    @Delete("/{id}")
    func remove(id: Int) async throws(APIError<ErrorDto>)
}
```

El macro genera `UsersAPIClient` con todas las funciones implementadas.

## Uso básico (async throws)

```swift
// GET con path param
let user = try await UsersAPIClient().fetch(id: 42)

// POST con body JSON
let newUser = try await UsersAPIClient().create(body: request)

// DELETE
try await UsersAPIClient().remove(id: 42)

// Con progress handler
let url = try await FilesAPIClient().download(id: "abc", onProgress: { progress in
    self.progressValue = progress.fractionCompleted
})
```

## Handles (progreso + cancelación + resume)

Para operaciones que necesitan control granular: tracking en Live Activities, cancelación con resume data, o binding a vistas.

```swift
// Crear handle con callback de progreso
let handle = FilesAPIClient().uploadTask(body: .multipart(...)) { progress in
    self.state.progress = progress
}

// Trackear en Live Activity
ProgressManager.shared.track(id: handle.id, message: "Subiendo archivo", stream: handle.progress)

// Ejecutar
try await handle.start()

// Cancelar con resume data
let resumeData = await handle.cancel()

// Reintentar desde donde se quedó
try await handle.start(resumeFrom: resumeData)
```

### Handle en SwiftUI (fullScreenCover)

Los handles son `Identifiable`, se pueden usar como binding para presentar vistas:

```swift
@State var uploadService: UploadTask<Void, ErrorDto>?

var body: some View {
    content
        .fullScreenCover(item: $uploadService) { handle in
            UploadProgressView(state: $state) {
                Task { await handle.cancel() }
            }
        }
}

func upload() async {
    let handle = FilesAPIClient().uploadTask(body: body) { progress in
        self.state.progress = progress
    }
    self.uploadService = handle

    do {
        try await handle.start()
    } catch { ... }

    self.uploadService = nil
}
```

## Parámetros

El macro detecta el rol de cada parámetro por **external label** (convención):

| External label | Rol | Ejemplo |
|-----------|-----|---------|
| `body` | Body JSON | `func create(body request: UserDto)` |
| `query` | Query param (key = nombre interno) | `func list(query page: Int)` |
| `header` | Header dinámico (key = nombre interno) | `func get(header token: String)` |
| `url` + tipo `URL` | URL absoluta (override de host + base + path) | `func download(url: URL)` |
| Tipo `[URLQueryItem]` | Query items directos | `func search(params: [URLQueryItem])` |
| Coincide con `{name}` en path | Path param | `@Get("/users/{id}") func get(id: Int)` |
| Tipo `HTTPBody` | Body raw (multipart, etc) | `func upload(body: HTTPBody)` |

> **Nota sobre uploads:** En endpoints con `task: .upload`, el parámetro `url: URL` mantiene su
> semántica de "fichero local" (sube desde disco) y NO activa el override de URL absoluta.

### Escapar colisiones

La detección se basa en el **external label**. Si el dominio tiene un campo que colisiona con una
convención reservada, usa el dual naming de Swift para escapar:

```swift
// "body" como body HTTP ✓
func create(body request: CreateRequest) async throws(APIError<E>) -> Item

// Campo de dominio "body" que NO es el body HTTP — external label distinto:
func update(_ body: BodyModel) async throws(APIError<E>) -> Item
func update(content body: BodyModel) async throws(APIError<E>) -> Item

// URL absoluta override ✓
func download(url: URL) async throws(APIError<E>) -> URL

// Parámetro URL que NO es override — external label distinto:
func process(target url: URL) async throws(APIError<E>) -> Result
```

## Task types

```swift
// Data (default) — request/response estándar
@Get("/users")
func list() async throws(APIError<ErrorDto>) -> [UserDto]

// Download — devuelve URL del fichero descargado
@Get("/file", task: .download)
func download() async throws(APIError<ErrorDto>) -> URL

// Upload — sube body con progreso real
@Put("/file", task: .upload)
func upload(body: FileDto) async throws(APIError<ErrorDto>)

// Bytes — streaming incremental (SSE, NDJSON, chunked)
@Get("/feed", task: .bytes)
func feed() async throws(APIError<ErrorDto>) -> ByteStream

// WebSocket — conexión bidireccional
@Socket("/chat")
func connect() -> WebSocketConnection<Message, ErrorDto>
```

### Download desde URL absoluta

Cuando el backend devuelve una URL completa (CDN, signed URLs, links de paginación), usa
`url: URL` para que el macro ignore el host + base configurados:

```swift
@API(host: "https://api.example.com", base: "/v2", ...)
protocol DocumentsAPI {
    // Download normal con path relativo
    @Get("/documents/{id}/file", task: .download)
    func downloadDocument(id: String) async throws(APIError<ErrorDto>) -> URL

    // Download desde URL absoluta (ignora host + base)
    @Get(task: .download)
    func download(url: URL) async throws(APIError<ErrorDto>) -> URL
}

// Uso:
let absoluteURL = URL(string: "https://cdn.example.com/files/doc.pdf?token=abc")!
let file = try await client.download(url: absoluteURL)
```

Auth, headers, interceptors y retry siguen aplicándose — solo cambia el destino de la petición.

## Variantes de Upload

El macro genera diferentes implementaciones según la firma del método en el protocolo:

| Firma | Método interno | Descripción |
|-------|----------------|-------------|
| `func upload(body: HTTPBody)` | `endpoint.upload()` | Sube el body serializado (multipart, json, etc.) en memoria |
| `func upload(url: URL)` | `endpoint.upload(url:)` | Sube directamente desde archivo en disco — ideal para archivos grandes sin cargarlos en memoria |

En todos los casos se generan las variantes con y sin `onProgress`, y el `Handle` correspondiente:

```swift
// Protocolo
@Put("/file", task: .upload)
func upload(body: HTTPBody) async throws(APIError<ErrorDto>)

@Put("/large-file", task: .upload)
func uploadFromDisk(url: URL) async throws(APIError<ErrorDto>)

// Generado:
// - upload(body:) / uploadFromDisk(url:)              → async throws
// - upload(body:onProgress:) / uploadFromDisk(url:onProgress:)  → async throws con progreso
// - uploadTask(body:) / uploadFromDiskTask()      → UploadTask (cancelable, resumable)
```

El `UploadTask` expone métodos directos para cada variante:

```swift
let handle = api.uploadHandle(body: body)

// Iniciar upload (usa body del endpoint)
try await handle.start()

// O subir desde archivo
try await handle.start(url: fileURL)

// O subir data explícita
try await handle.start(data: rawData)

// Cancelar y obtener resume data
let resumeData = await handle.cancel()

// Reanudar
try await handle.start(resumeFrom: resumeData)
```

## Config por ruta

Cada endpoint puede tener su propia configuración de retry y timeout:

```swift
@Get("/critical-data", config: RequestConfig(retry: .resilient, timeout: 120))
func fetchCritical() async throws(APIError<ErrorDto>) -> CriticalDto

@Post("/fire-and-forget", config: RequestConfig(retry: .none, timeout: 10))
func notify(body: NotifyRequest) async throws(APIError<ErrorDto>)
```

## Interceptors

Los interceptors permiten modificar requests antes de enviarlas e inspeccionar respuestas:

```swift
struct MetricsInterceptor: RequestInterceptor {
    func intercept(request: URLRequest) async -> URLRequest {
        var req = request
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        return req
    }

    func didReceive(response: HTTPURLResponse, data: Data, for request: URLRequest) async {
        MetricsService.shared.track(
            path: request.url?.path() ?? "",
            status: response.statusCode
        )
    }
}
```

Se aplican a nivel de `@API` o por ruta:

```swift
// A nivel de configuración global (DSL component)
Intercept([MetricsInterceptor(), DeviceHeaderInterceptor()])

// Directamente en el builder
let endpoint = Endpoint<Response, Error>(
    client: client,
    interceptors: [MetricsInterceptor()],
    api: request
)
```

## Typed throws

Los errores están tipados. El tipo de error se infiere del `throws` clause o del parámetro `error:` de la ruta:

```swift
// Error por defecto del @API
@API(host: ..., error: ErrorDto.self)
protocol MyAPI {
    @Get("/data")
    func fetch() async throws(APIError<ErrorDto>) -> DataDto
}

// Error específico por ruta
@Post("/legacy", error: OldErrorDto.self)
func legacyCall() async throws(APIError<OldErrorDto>)
```

Esto permite pattern matching tipado en el catch:

```swift
do {
    try await api.fetch()
} catch let error {
    // error.body es de tipo ErrorDto? — acceso directo al body del error del servidor
    showAlert(error.body?.message ?? "Error desconocido")
}
```

## WebSocket

```swift
@API(host: "wss://ws.example.com", ...)
protocol ChatAPI {
    @Socket("/chat/{roomId}")
    func connect(roomId: String) async throws(APIError<ErrorDto>) -> WebSocketConnection<ChatMessage, ErrorDto>
}

// Uso
let connection = try await ChatAPIClient().connect(roomId: "room-42")

for try await event in connection {
    switch event {
    case .message(let msg): handle(msg)
    case .reconnecting(let attempt, _): showReconnecting()
    case .reconnected: hideReconnecting()
    }
}

try await connection.send(ChatMessage(text: "Hola"))
await connection.disconnect()
```

## Override de client por instancia

```swift
// Usar un client diferente para una llamada específica
let result = try await UsersAPIClient(client: Client(session: customSession)).fetch(id: 1)
```

## Mock Generation

Para facilitar el testing sin dependencias de red, `@API` puede generar un mock automáticamente:

```swift
@API(
    host: "https://api.example.com",
    base: "/v2/users",
    auth: AuthManager.shared,
    mock: true
)
protocol UsersAPI {
    @Get("/{id}")
    func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto

    @Post("")
    func create(body request: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto

    @Delete("/{id}")
    func remove(id: Int) async throws(APIError<ErrorDto>)
}
```

Con `mock: true`, el macro genera `UsersAPIMock` además del `UsersAPIClient`:

```swift
struct UsersAPIMock: UsersAPI {
    var fetchMock: (Int) async throws(APIError<ErrorDto>) -> UserDto = { _ in
        fatalError("UsersAPIMock.fetch not stubbed")
    }
    var createMock: (CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto = { _ in
        fatalError("UsersAPIMock.create not stubbed")
    }
    var removeMock: (Int) async throws(APIError<ErrorDto>) -> Void = { _ in
        fatalError("UsersAPIMock.remove not stubbed")
    }
    // + protocol-conforming methods that delegate to each handler
}
```

### Uso en tests

```swift
@Test func fetchUser() async throws {
    var mock = UsersAPIMock()
    mock.fetchMock = { id in UserDto(id: id, name: "Test") }

    let viewModel = UsersViewModel(api: mock)
    await viewModel.load(userId: 42)

    #expect(viewModel.user?.name == "Test")
}

@Test func fetchUserError() async {
    var mock = UsersAPIMock()
    mock.fetchMock = { (_) async throws(APIError<ErrorDto>) in
        throw APIError.noConnection
    }

    let viewModel = UsersViewModel(api: mock)
    await viewModel.load(userId: 1)

    #expect(viewModel.error == .noConnection)
}
```

### Convención de nombres

Cada método `func xyz(...)` genera una propiedad `var xyzMock`. Si hay overloads con el mismo nombre, se desambigua con el primer parámetro: `uploadBodyMock`, `uploadUrlMock`.

Si `mock:` no se especifica (o es `false`), no se genera nada — la feature es completamente invisible.

## Streaming (ByteStream)

Para endpoints que devuelven datos de forma incremental (SSE, NDJSON, chunked), usa `task: .bytes`:

```swift
@API(host: "https://api.example.com", base: "/v1", auth: AuthManager.shared)
protocol ChatAPI {
    @Post("/completions", task: .bytes)
    func complete(body request: CompletionRequest) async throws(APIError<ErrorDto>) -> ByteStream

    @Get("/feed", task: .bytes)
    func feed() async throws(APIError<ErrorDto>) -> ByteStream
}
```

El macro genera la variante async throws. Para cancelar, cancela la `Task` que envuelve la iteración:

```swift
// Async throws (se cancela con Task.cancel / .task { } en SwiftUI)
let stream = try await ChatAPIClient().complete(body: request)

// Cancelación explícita
let task = Task {
    let stream = try await ChatAPIClient().complete(body: request)
    for try await chunk in stream.sseEvents() {
        self.text += chunk.delta
    }
}
// Desde otro contexto:
task.cancel()
```

### Consumir el stream

`ByteStream` es un wrapper autenticado. El caller decide cómo parsearlo:

```swift
// Como JSON Lines (NDJSON) — cada línea es un JSON independiente
for try await chunk in stream.jsonLines(CompletionChunk.self) {
    self.text += chunk.delta
}

// Como Server-Sent Events (SSE) — protocolo text/event-stream
for try await chunk in stream.sseEvents(CompletionChunk.self) {
    self.text += chunk.delta
}

// SSE raw (acceso a event type, id, retry)
for try await event in stream.sseRawEvents() {
    switch event.event {
    case "delta": handleDelta(event.data)
    case "done": break
    default: continue
    }
}

// Líneas raw
for try await line in stream.lines {
    print(line)
}
```

### Retry

El `RetryPolicy` configurado aplica a la **conexión inicial**. Una vez que el stream está activo, los errores mid-stream se propagan directamente al caller.

## HTTPBody

Representa el cuerpo de un request saliente. Cada case determina el `Content-Type` implícitamente:

```swift
// JSON (más común) — cualquier Encodable & Sendable
let body: HTTPBody = .json(LoginRequest(email: "user@mail.com", password: "secret"))

// Form URL-Encoded — para OAuth, APIs legacy
let body: HTTPBody = .formURLEncoded([
    URLQueryItem(name: "grant_type", value: "authorization_code"),
    URLQueryItem(name: "code", value: authCode),
    URLQueryItem(name: "client_id", value: clientId),
    URLQueryItem(name: "redirect_uri", value: redirectURI)
])

// Raw data con content type explícito
let body: HTTPBody = .data(videoData, contentType: .video(format: .mp4))
let body: HTTPBody = .data(rawBytes) // default: application/octet-stream

// Multipart form data (file uploads)
let form = MultipartForm(
    parameters: ["description": "Profile photo"],
    media: [Media(url: photoURL, key: "file")]
)
let body: HTTPBody = .multipart(form)
```

| Case | Content-Type |
|------|-------------|
| `.json(value)` | `application/json; charset=UTF-8` |
| `.data(data, contentType:)` | Explicit (default: `application/octet-stream`) |
| `.multipart(form)` | `multipart/form-data; boundary=...` |
| `.formURLEncoded(items)` | `application/x-www-form-urlencoded` |

## Autenticación

Beam ofrece tres tipos de auth provider que conforman `AuthProtocol`:

### TokenAuth (refresh automático)

Para tokens con expiración (Bearer, OAuth2). Gestiona auto-refresh, deduplicación de refresh concurrentes, y espera a token inicial:

```swift
// Bearer (por defecto aplica Authorization: Bearer <token>)
let auth = TokenAuth {
    let response = try await api.refreshToken()
    return .init(value: response.accessToken, expiration: response.expiration)
}

// Custom headers — el token se resuelve y se pasa al closure
let auth = TokenAuth(
    refresh: {
        let response = try await api.refreshToken()
        return .init(value: response.accessToken, expiration: response.expiration)
    },
    apply: { token, request in
        request.addValue(clientId, forHTTPHeaderField: "client_id")
        request.addValue(clientSecret, forHTTPHeaderField: "client_secret")
        request.addValue(token.value, forHTTPHeaderField: "authToken")
    }
)
```

Lifecycle:

```swift
// Tras login: proporcionar token inicial
await auth.set(token: .init(value: jwt, expiration: expiry))

// Tras logout: limpia estado, cancela refresh pendiente
await auth.clear()
```

### SignedAuth (HMAC / firma por request)

Para APIs que requieren una firma computada sobre el request (método, path, body, timestamp):

```swift
let auth = SignedAuth(name: "HMAC") { request in
    let timestamp = "\(Int(Date.now.timeIntervalSince1970))"
    let payload = [request.httpMethod ?? "GET", request.url?.path ?? "/", timestamp].joined(separator: "\n")
    let signature = HMAC.sign(payload: payload, secret: secret)
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.addValue(timestamp, forHTTPHeaderField: "X-Timestamp")
    request.addValue(signature, forHTTPHeaderField: "X-Signature")
}
```

### StaticAuth (API keys fijas)

Para credenciales que nunca cambian:

```swift
let auth = StaticAuth(name: "APIKey") { request in
    request.addValue("my-secret-key", forHTTPHeaderField: "X-API-Key")
}

// Múltiples headers estáticos
let auth = StaticAuth(name: "Platform") { request in
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.addValue(appId, forHTTPHeaderField: "X-App-ID")
}
```

### AuthProtocol (custom)

Para implementar un provider completamente custom:

```swift
actor MyAuth: AuthProtocol {
    func authenticate(request: inout URLRequest) async throws {
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    func invalidate() async { /* mark token as stale */ }
}
```

## Logging

Beam incluye logging integrado con `os.Logger` y signposts. Configurable globalmente vía `BeamLog`:

```swift
// Ver bodies completos de request y response en consola:
BeamLog.verbose = true

// Cambiar nivel mínimo de log:
BeamLog.level = .warning

// Desactivar todo el logging:
BeamLog.enabled = false
```

| Propiedad | Default | Efecto |
|-----------|---------|--------|
| `enabled` | `true` | Activa/desactiva todos los logs |
| `level` | `.debug` | Nivel mínimo global (debug, info, warning, error, off) |
| `verbose` | `false` | Imprime bodies completos (request y response) sin límite |

Cada endpoint puede override el nivel con `logLevel:` en el init:

```swift
@Get("/noisy", config: .standard)
func noisy() async throws(APIError<ErrorDto>) -> NoisyDto // uses global level

// En código manual:
let endpoint = Endpoint<T, E>(..., logLevel: .warning, api: request)
```

## Arquitectura

```
Beam/
├── Service/
│   ├── APIMacroSupport.swift   — @API, @Get, @Post... macro declarations
│   ├── Handles.swift           — DownloadHandle, UploadHandle, StreamHandle, ProgressHandler
│   ├── RouteBuilder.swift      — _buildRoute() (usado por código generado)
│   ├── Service.swift           — Core: retry, download, upload, websocket, error mapping
│   └── RetryPolicy.swift       — Configuración de reintentos y StreamEvent
├── Client/
│   ├── Client.swift            — Actor URLSession con progress, cancel, SSL pinning
│   ├── NetworkDelegate.swift   — URLSessionTaskDelegate para progreso y pinning
│   └── URLSessionConformance.swift — SessionProtocol protocol
├── Request/
│   ├── APIRequest.swift        — Value type con method, host, path, headers, body
│   ├── RequestBuilder.swift    — RequestBuilderState
│   ├── RequestComponents.swift — Header, Use, Auth, Crash, Config, Intercept components
│   ├── RequestConfig.swift     — Timeout, retry, ping interval
│   └── RequestInterceptor.swift — Protocol para interceptar requests/responses
├── Auth/                       — TokenAuth, SignedAuth, StaticAuth, AuthProtocol
├── HTTP/                       — HTTPBody, HTTPMethod, HTTPStatus, MultipartForm, ContentType
├── Error/                      — APIError<F>, ClientError, AuthError, SerializerError
├── Serializer/                 — JSON encode/decode con soporte para Void, String, Data, UIImage
└── Support/                    — Logger, FileUtils, CrashProtocol, SSEParser, JSONLinesParser
```
