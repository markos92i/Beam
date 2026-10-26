//
//  Call+Perform.swift
//  Beam
//
//  The attempt loop: build → interceptors → auth → send → interceptors + validation
//  → output, with the 401 refresh and the retry policy, notifying the monitors.
//

import Foundation

enum Payload: Sendable {
    case data(Data)
    case file(URL)
    /// URLSession resumes with the request stored in the resume data.
    case resume(Data)
}

extension Call {
    /// An upload's body travels as payload, not `httpBody`: URLSession ignores a request's body in uploads.
    func perform<Output>(
        _ operation: EndpointContext.Operation,
        accept: ContentType? = nil,
        uploading content: UploadContent? = nil,
        resumeFrom resumeData: Data? = nil,
        after previous: (error: APIError<Failure>, attempt: EndpointContext.Attempt)? = nil,
        observers: [any Monitor] = [],
        send: (URLRequest, Payload?) async throws(APIError<Failure>) -> Response,
        output: (Response) async throws(APIError<Failure>) -> sending Output
    ) async throws(APIError<Failure>) -> Output {
        let monitors = allMonitors + observers
        var resumeData = resumeData
        var encoded: Data?
        let clock = ContinuousClock()
        let start = clock.now
        var attempts: [EndpointContext.Attempt] = []
        var policyRetries = 0
        var refreshedAuth = false
        var lastRequest: URLRequest?
        var lastResponse: Response?
        var pending: (error: APIError<Failure>, context: EndpointContext)?

        func fail(_ error: APIError<Failure>, _ context: EndpointContext) -> APIError<Failure> {
            let failure = EndpointFailure(
                error: error.asVoid, request: lastRequest?.withoutCredentials, response: lastResponse,
                method: route.method, host: route.host, path: route.path, pathTemplate: route.pathTemplate,
                attempt: context.attempt
            )
            for monitor in monitors { monitor.didFail(failure, context: context) }
            return error
        }

        if let previous {
            attempts.append(previous.attempt)
            pending = (previous.error, EndpointContext(
                id: id, method: route.method, pathTemplate: route.pathTemplate, operation: operation,
                attempt: 0, attempts: attempts, elapsed: .zero
            ))
        }

        while true {
            if let failure = pending {
                pending = nil
                let (error, finished) = failure

                guard !Task.isCancelled else { throw fail(.cancelled, finished) }

                if error.status == .unauthorized, let auth, !refreshedAuth {
                    // Refresh and repeat once, outside the retry policy.
                    refreshedAuth = true
                    await auth.invalidate()
                    for monitor in monitors { monitor.willRetry(after: error.asVoid, delay: .zero, context: finished) }
                } else {
                    guard policyRetries < config.retry.maxAttempts, error.isRetryable else { throw fail(error, finished) }
                    policyRetries += 1
                    let delay = config.retry.delay(for: policyRetries)
                    for monitor in monitors { monitor.willRetry(after: error.asVoid, delay: delay, context: finished) }
                    if delay > .zero {
                        do { try await Task.sleep(for: delay) } catch { throw fail(.cancelled, finished) }
                    }
                }
            }

            let context = EndpointContext(
                id: id, method: route.method, pathTemplate: route.pathTemplate, operation: operation,
                attempt: attempts.count, attempts: attempts, elapsed: clock.now - start
            )
            let attemptStart = clock.now
            var status: Int?

            do throws(APIError<Failure>) {
                var request = try makeRequest(accept: accept, contentType: content?.contentType)
                var payload: Payload?
                if let content {
                    guard route.body == nil else { throw .conflictingUploadData }
                    // A resumed attempt sends the resume data instead.
                    if resumeData == nil {
                        switch content {
                        case .file(let url): payload = .file(url)
                        case .body(let body): payload = .data(try await encode(body, once: &encoded))
                        }
                    }
                } else if let body = route.body {
                    request.httpBody = try await encode(body, once: &encoded)
                }
                request = try await intercept(request: request, context: context)
                request = try await authenticate(request)
                lastRequest = request
                if Task.isCancelled { throw .cancelled }
                if let resume = resumeData {
                    payload = .resume(resume)
                    resumeData = nil
                }
                let sent = request.withoutCredentials
                for monitor in monitors { monitor.didSend(sent, context: context) }

                let received = try await send(request, payload)
                status = received.http.statusCode
                lastResponse = received
                for monitor in monitors { monitor.didReceive(received, context: context) }

                let response = try await intercept(response: received, context: context)
                let value = try await output(response)

                attempts.append(.init(status: status, duration: clock.now - attemptStart))
                for monitor in monitors { monitor.didSucceed(response, context: context.finished(attempts: attempts, elapsed: clock.now - start)) }
                return value
            } catch {
                attempts.append(.init(status: status, duration: clock.now - attemptStart))
                pending = (error, context.finished(attempts: attempts, elapsed: clock.now - start))
            }
        }
    }

    var allMonitors: [any Monitor] {
        [LogMonitor(log: log, maxAttempts: config.retry.maxAttempts)] + monitors
    }

    // MARK: - Steps

    func makeRequest(accept: ContentType? = nil, contentType: ContentType? = nil) throws(APIError<Failure>) -> URLRequest {
        if let missingValue = route.missingValue {
            throw .missingValue(missingValue)
        }
        guard let url = route.url else {
            throw .invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = route.method.rawValue

        var headers = route.allHeaders
        if let contentType { headers = contentType.header.merging(headers) { _, route in route } }
        if let accept, headers["Accept"] == nil {
            headers["Accept"] = accept.value
        }

        request.allHTTPHeaderFields = headers
        request.timeoutInterval = config.timeout.timeInterval
        return request
    }

    private func encode(_ body: HTTPBody, once encoded: inout Data?) async throws(APIError<Failure>) -> Data {
        if let encoded { return encoded }
        let data = try await encode(body)
        encoded = data
        return data
    }

    /// `@concurrent` keeps encoding and multipart file reads off the caller's actor.
    @concurrent
    private func encode(_ body: HTTPBody) async throws(APIError<Failure>) -> Data {
        switch body {
        case .json(let value):
            do { return try config.json.encode(value) } catch { throw .coding(error) }
        case .data(let raw, _):
            return raw
        case .multipart(let form):
            do { return try form.body } catch { throw .storage(error) }
        case .formURLEncoded(let items):
            return items.formEncoded()
        }
    }

    private func intercept(request: URLRequest, context: EndpointContext) async throws(APIError<Failure>) -> URLRequest {
        var request = request
        for interceptor in interceptors {
            do {
                request = try await interceptor.intercept(request: request, context: context)
            } catch {
                throw APIError(error, response: nil, decodeBody: decodeErrorBody)
            }
        }
        return request
    }

    private func intercept(response: Response, context: EndpointContext) async throws(APIError<Failure>) -> Response {
        var response = response
        for interceptor in interceptors + [ValidationInterceptor()] {
            do {
                response = try await interceptor.intercept(response: response, context: context)
            } catch {
                throw APIError(error, response: response.http, decodeBody: decodeErrorBody)
            }
        }
        return response
    }

    /// Runs after the interceptors: a signature has to see the final request.
    private func authenticate(_ request: URLRequest) async throws(APIError<Failure>) -> URLRequest {
        guard let auth else { return request }
        var request = request
        switch config.authPolicy {
        case .required:
            do { try await auth.authenticate(request: &request) } catch { throw APIError(error) }
        case .optional:
            try? await auth.authenticate(request: &request)
        }
        return request
    }

    /// Logs undecodable bodies: usually the server answered with another error format.
    private func decodeErrorBody(_ data: Data?) -> HTTPErrorBody<Failure> {
        guard let data, !data.isEmpty else { return HTTPErrorBody(data: data) }
        do {
            return HTTPErrorBody(try errorBody.decode(data, with: config.json), data: data)
        } catch {
            log.log(.undecodedErrorBody(id: id, type: "\(Failure.self)", detail: error.logDescription))
            return HTTPErrorBody(data: data, decodingError: error)
        }
    }
}

extension EndpointContext {
    func finished(attempts: [Attempt], elapsed: Duration) -> EndpointContext {
        EndpointContext(
            id: id, method: method, pathTemplate: pathTemplate, operation: operation,
            attempt: attempt, attempts: attempts, elapsed: elapsed
        )
    }
}
