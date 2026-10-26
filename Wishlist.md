# Beam — Wishlist

Features pospuestas para futuras versiones. Cada entrada incluye contexto suficiente para retomarla sin necesidad de buscar el hilo original.

---

## Retry condicional personalizable

Actualmente `isRetryable` está hardcoded en `TransportError`. Permitir un closure de decisión en `RetryPolicy` para que el consumidor defina qué errores reintentar:

```swift
RetryPolicy(
    maxAttempts: 3,
    strategy: .exponential(base: 1, maxDelay: 10),
    shouldRetry: { error in error.status != .conflict }
)
```

---

## 429 Rate Limit awareness

Detección automática de respuestas `429 Too Many Requests` con lectura del header `Retry-After`. Back-off adaptativo sin consumir intentos del retry policy configurado. El endpoint esperaría el tiempo indicado por el servidor antes de reintentar.

---

## Métricas estructuradas

Un `MetricsCollector` protocol que reciba eventos tipados (latencia, status code, retries, bytes transferidos) en vez de depender de interceptors genéricos. Integrable con `os_signpost` pero también exportable a backends de analytics:

```swift
@API(host: ..., metrics: AppMetrics.shared)
```

---

## Multipart streaming

Actualmente `MultipartForm.body` serializa todo a `Data` en memoria. Para archivos grandes, implementar un upload que haga stream directo desde disco sin cargar el contenido completo en memoria.

---

## Destino configurable en downloads

Ahora el download siempre copia a `cachesDirectory`. Permitir configurar el directorio destino por endpoint o por llamada, o que el response interceptor pueda decidirlo explícitamente.

---

## Config composition

Cuando múltiples protocolos comparten auth, session, crash, etc., un mecanismo para extraer la configuración común y no repetirla en cada `@API`:

```swift
let sharedConfig = BeamConfig(host: ..., auth: ..., crash: ...)

@API(config: sharedConfig, base: "/v2/users")
protocol UsersAPI { ... }

@API(config: sharedConfig, base: "/v2/orders")
protocol OrdersAPI { ... }
```

---

## Diagnósticos de la macro

Los tipos no soportados ya dan un error claro (overloads `unavailable` de `_Route`). Quedan los fallos que dependen de la estructura y no del tipo:

- Placeholder `{id}` en el path sin parámetro que case → hoy da un error críptico dentro de la expansión.
- Método del protocolo sin `@Get/@Post/...` → se ignora y acaba en un "does not conform" confuso.
- Método con `throws` sin tipar → se genera `APIError<Void>` en silencio (contra la regla de typed throws del proyecto).

## Formato de arrays en query

`query ids: [Int]` no compila a propósito (mensaje explícito) hasta decidir el formato que esperan los backends: clave repetida (`ids=1&ids=2`) o separado por comas (`ids=1,2`). Es una sola sobrecarga en `_Route.query`; la app no usa arrays en query hoy.

Emitir `Diagnostic` sobre el miembro concreto, con fix-it cuando sea posible.

---

## Simplificar los métodos de `Endpoint`

`Endpoint` tiene 12 métodos públicos casi idénticos (`data`, `upload*`, `download*`, `uploadTask*`, `downloadTask*`): todos son `perform { … decodeDataResponse }` o `perform { … resolveDownloadResponse }`. Con dos helpers privados (uno que decodifica `(Data, HTTPURLResponse)` y otro para ficheros) y un `uploadBody()` para el guard de `missingUploadData`, cada método queda en una línea sin cambiar la API pública.

---

## `ByteStream.allLines` sin task no estructurada

`allLines` crea un `Task` y un `AsyncThrowingStream` para partir líneas conservando las vacías (necesario para SSE). Ese tipo se filtra a la API pública: `SSESequence<AsyncThrowingStream<String, Error>, Element>`. Sustituirlo por un `AsyncSequence` propio que itere los bytes directamente (sin task, cancelación y backpressure naturales) y devolver `some AsyncSequence<Element, any Error>` desde `sseEvents()` / `sseRawEvents()`. Verificado que ese tipo opaco compila con target iOS 18.

---

## Cancelación en el camino de handles (`UploadTask` / `DownloadTask`)

En el camino async (`data`, `upload`, `download`) cancelar la Swift Task cancela la transferencia. En el camino de handles, `SessionDelegate.awaitDownload/awaitUpload` usan `withCheckedThrowingContinuation` sin `withTaskCancellationHandler`: cancelar la Swift Task no hace nada, solo `handle.cancel()`. Decidir el comportamiento: en sesión background quizá la transferencia debe seguir, pero al menos el que espera debería dejar de esperar (y la cancelación debería resolverse igual en ambos caminos).

---

## `UploadTask.start(resumeFrom:)` usa el camino foreground

`start()`, `start(data:)` y `start(url:)` usan `endpoint.uploadTask*` (compatible con background), pero `start(resumeFrom:)` llama a `endpoint.upload(resumeFrom:)` (foreground). Valorar un `uploadTask(withResumeData:)` en `Client`/`SessionProtocol` para que el handle sea coherente.

---

## Igualdad de `APIError`

`APIError ==` compara solo `id`: `.connectionClosed(code: 1000) == .connectionClosed(code: 1006)` y dos `.http(status: 500)` con body distinto son `true`. Si la intención es "mismo tipo de error", hacerlo explícito (p. ej. una propiedad `kind` o `~=`) y que `==` compare valores cuando `Failure: Equatable`.
