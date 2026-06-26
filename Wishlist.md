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
