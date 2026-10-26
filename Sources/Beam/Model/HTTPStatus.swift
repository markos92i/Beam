//
//  HTTPStatus.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 5/1/25.
//

import Foundation

/// An HTTP status: the IETF codes plus common unofficial ones (nginx, Cloudflare).
public enum HTTPStatus: Int, Error, CustomStringConvertible {

    /// Status classes, by the code's first digit.
    public enum ResponseType {
        case informational
        case success
        case redirection
        case clientError
        case serverError
        case undefined
    }

    case undefined = 0

    // MARK: - Informational - 1xx

    case `continue` = 100
    case switchingProtocols = 101
    case processing = 102
    case earlyHints = 103

    // MARK: - Success - 2xx

    case ok = 200
    case created = 201
    case accepted = 202
    case nonAuthoritativeInformation = 203
    case noContent = 204
    case resetContent = 205
    case partialContent = 206
    case multiStatus = 207
    case alreadyReported = 208
    case IMUsed = 226

    // MARK: - Redirection - 3xx

    case multipleChoices = 300
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case useProxy = 305
    case switchProxy = 306
    case temporaryRedirect = 307
    case permanentRedirect = 308

    // MARK: - Client Error - 4xx

    case badRequest = 400
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case proxyAuthenticationRequired = 407
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case payloadTooLarge = 413
    case URITooLong = 414
    case unsupportedMediaType = 415
    case rangeNotSatisfiable = 416
    case expectationFailed = 417
    case teapot = 418
    case misdirectedRequest = 421
    case unprocessableEntity = 422
    case locked = 423
    case failedDependency = 424
    case tooEarly = 425
    case upgradeRequired = 426
    case preconditionRequired = 428
    case tooManyRequests = 429
    case requestHeaderFieldsTooLarge = 431
    case noResponse = 444
    case unavailableForLegalReasons = 451
    case SSLCertificateError = 495
    case SSLCertificateRequired = 496
    case HTTPRequestSentToHTTPSPort = 497
    case clientClosedRequest = 499

    // MARK: - Server Error - 5xx

    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case HTTPVersionNotSupported = 505
    case variantAlsoNegotiates = 506
    case insufficientStorage = 507
    case loopDetected = 508
    case bandwidthLimitExceeded = 509
    case notExtended = 510
    case networkAuthenticationRequired = 511

    // MARK: - Cloudflare - 52x, 530 (unofficial, sent by the CDN in front of the origin)

    case webServerReturnedUnknownError = 520
    case webServerIsDown = 521
    case connectionTimedOut = 522
    case originIsUnreachable = 523
    case timeoutOccurred = 524
    case SSLHandshakeFailed = 525
    case invalidSSLCertificate = 526
    case railgunError = 527
    case originDNSError = 530

    /// A failure another attempt can fix: a timeout, an overloaded server, or a gateway (Cloudflare's too)
    /// that couldn't get an answer from the origin. 501, 505 or an SSL misconfiguration (525, 526) can't.
    var isTransient: Bool {
        switch self {
        case .requestTimeout, .internalServerError, .badGateway, .serviceUnavailable, .gatewayTimeout,
             .webServerReturnedUnknownError, .webServerIsDown, .connectionTimedOut, .originIsUnreachable, .timeoutOccurred:
            true
        default:
            false
        }
    }

    /// The class the status belongs to.
    public var type: ResponseType {
        switch self.rawValue {
        case 100..<200: .informational
        case 200..<300: .success
        case 300..<400: .redirection
        case 400..<500: .clientError
        case 500..<600: .serverError
        default:        .undefined
        }
    }

    public var name: String {
        switch self {
        case .continue:                     "Continue"
        case .switchingProtocols:           "Switching Protocols"
        case .processing:                   "Processing"
        case .earlyHints:                   "Early Hints"
        case .ok:                           "OK"
        case .created:                      "Created"
        case .accepted:                     "Accepted"
        case .nonAuthoritativeInformation:  "Non-Authoritative Information"
        case .noContent:                    "No Content"
        case .resetContent:                 "Reset Content"
        case .partialContent:               "Partial Content"
        case .multiStatus:                  "Multi-Status"
        case .alreadyReported:              "Already Reported"
        case .IMUsed:                       "IM Used"
        case .multipleChoices:              "Multiple Choices"
        case .movedPermanently:             "Moved Permanently"
        case .found:                        "Found"
        case .seeOther:                     "See Other"
        case .notModified:                  "Not Modified"
        case .useProxy:                     "Use Proxy"
        case .switchProxy:                  "Switch Proxy"
        case .temporaryRedirect:            "Temporary Redirect"
        case .permanentRedirect:            "Permanent Redirect"
        case .badRequest:                   "Bad Request"
        case .unauthorized:                 "Unauthorized"
        case .paymentRequired:              "Payment Required"
        case .forbidden:                    "Forbidden"
        case .notFound:                     "Not Found"
        case .methodNotAllowed:             "Method Not Allowed"
        case .notAcceptable:                "Not Acceptable"
        case .proxyAuthenticationRequired:  "Proxy Authentication Required"
        case .requestTimeout:               "Request Timeout"
        case .conflict:                     "Conflict"
        case .gone:                         "Gone"
        case .lengthRequired:               "Length Required"
        case .preconditionFailed:           "Precondition Failed"
        case .payloadTooLarge:              "Payload Too Large"
        case .URITooLong:                   "URI Too Long"
        case .unsupportedMediaType:         "Unsupported Media Type"
        case .rangeNotSatisfiable:          "Range Not Satisfiable"
        case .expectationFailed:            "Expectation Failed"
        case .teapot:                       "I'm a Teapot"
        case .misdirectedRequest:           "Misdirected Request"
        case .unprocessableEntity:          "Unprocessable Entity"
        case .locked:                       "Locked"
        case .failedDependency:             "Failed Dependency"
        case .tooEarly:                     "Too Early"
        case .upgradeRequired:              "Upgrade Required"
        case .preconditionRequired:         "Precondition Required"
        case .tooManyRequests:              "Too Many Requests"
        case .requestHeaderFieldsTooLarge:  "Request Header Fields Too Large"
        case .noResponse:                   "No Response"
        case .unavailableForLegalReasons:   "Unavailable For Legal Reasons"
        case .SSLCertificateError:          "SSL Certificate Error"
        case .SSLCertificateRequired:       "SSL Certificate Required"
        case .HTTPRequestSentToHTTPSPort:   "HTTP Request Sent to HTTPS Port"
        case .clientClosedRequest:          "Client Closed Request"
        case .internalServerError:          "Internal Server Error"
        case .notImplemented:               "Not Implemented"
        case .badGateway:                   "Bad Gateway"
        case .serviceUnavailable:           "Service Unavailable"
        case .gatewayTimeout:               "Gateway Timeout"
        case .HTTPVersionNotSupported:      "HTTP Version Not Supported"
        case .variantAlsoNegotiates:        "Variant Also Negotiates"
        case .insufficientStorage:          "Insufficient Storage"
        case .loopDetected:                 "Loop Detected"
        case .bandwidthLimitExceeded:       "Bandwidth Limit Exceeded"
        case .notExtended:                  "Not Extended"
        case .networkAuthenticationRequired: "Network Authentication Required"
        case .webServerReturnedUnknownError: "Web Server Returned an Unknown Error"
        case .webServerIsDown:              "Web Server Is Down"
        case .connectionTimedOut:           "Connection Timed Out"
        case .originIsUnreachable:          "Origin Is Unreachable"
        case .timeoutOccurred:              "A Timeout Occurred"
        case .SSLHandshakeFailed:           "SSL Handshake Failed"
        case .invalidSSLCertificate:        "Invalid SSL Certificate"
        case .railgunError:                 "Railgun Error"
        case .originDNSError:               "Origin DNS Error"
        case .undefined:                    "Undefined"
        }
    }

    public var description: String { "\(rawValue) \(name)" }
}

extension HTTPURLResponse {
    var httpStatus: HTTPStatus { HTTPStatus(rawValue: statusCode) ?? .undefined }
}

extension HTTPStatus {
    /// The single success rule for every response kind (attempts, streams, background results).
    func succeeds(for operation: EndpointContext.Operation) -> Bool {
        operation == .connection ? self == .switchingProtocols : type == .success
    }
}
