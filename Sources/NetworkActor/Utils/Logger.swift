//
//  Logger.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

// MARK: - Logger Levels
public enum LogLevel: Int, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    var prefix: String {
        switch self {
        case .debug:   "⚪️ DEBUG"
        case .info:    "🔵 INFO"
        case .warning: "🟠 WARNING"
        case .error:   "🔴 ERROR"
        }
    }
}

// MARK: - Logger
struct Logger {
    private let minimumLevel: LogLevel
    
    public init(minimumLevel: LogLevel = .debug) {
        self.minimumLevel = minimumLevel
    }
    
    public func log(_ message: @autoclosure () -> String,
                    level: LogLevel,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        guard level.rawValue >= minimumLevel.rawValue else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = "[\(fileName):\(line)] \(function) - \(message())"
        
        print("\(level.prefix) \(formattedMessage)")
    }
    
    // Métodos de conveniencia
    public func debug(_ msg: @autoclosure () -> String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        log(msg(), level: .debug, file: file, function: function, line: line)
    }
    
    public func info(_ msg: @autoclosure () -> String,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line) {
        log(msg(), level: .info, file: file, function: function, line: line)
    }
    
    public func warning(_ msg: @autoclosure () -> String,
                        file: String = #file,
                        function: String = #function,
                        line: Int = #line) {
        log(msg(), level: .warning, file: file, function: function, line: line)
    }
    
    public func error(_ msg: @autoclosure () -> String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        log(msg(), level: .error, file: file, function: function, line: line)
    }
}

// MARK: - Pretty JSON Helper (puede ir en otro archivo)
public struct JSONHelper {
    public static func prettyString(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8)
        }
        return prettyString
    }
}
