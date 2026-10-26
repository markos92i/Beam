//
//  FileUtils.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

enum FileUtils {
    static func resolveFilename(suggestedFilename: String?, contentType: ContentType) -> String {
        let name = suggestedFilename.flatMap { $0.isEmpty ? nil : $0 }
        if let name, !URL(fileURLWithPath: name).pathExtension.isEmpty { return name }
        let ext = contentType.utType?.preferredFilenameExtension
            ?? String(contentType.mediaType.split(separator: "/").last ?? "bin")
        return "\(name ?? UUID().uuidString).\(ext)"
    }

    /// Foundation's file errors are untyped but documented as `CocoaError`.
    static func bridging<T>(_ wrap: (CocoaError) -> FileError, _ fallback: CocoaError.Code, _ operation: () throws -> T) throws(FileError) -> T {
        do { return try operation() } catch { throw wrap(CocoaError(bridging: error, fallback: fallback)) }
    }

    // MARK: - Downloads

    /// A folder of its own, so two downloads with the same name never replace each other.
    static func store(_ source: URL, for response: HTTPURLResponse) throws(FileError) -> URL {
        let folder = URL.cachesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = resolveFilename(suggestedFilename: response.suggestedFilename, contentType: response.contentType ?? .data)
        let target = folder.appendingPathComponent(name)
        try createDirectory(folder)
        try move(source, to: target)
        return target
    }

    static func temporaryLocation(_ kind: String = "download") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Beam-\(kind)-\(UUID().uuidString)")
    }

    static func createDirectory(_ folder: URL) throws(FileError) {
        try bridging(FileError.writeFailed, .fileWriteUnknown) { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    /// Atomic: a reader never sees it half written.
    static func write(_ data: Data, to url: URL) throws(FileError) {
        try bridging(FileError.writeFailed, .fileWriteUnknown) { try data.write(to: url, options: .atomic) }
    }

    static func move(_ source: URL, to target: URL) throws(FileError) {
        try bridging(FileError.moveFailed, .fileWriteUnknown) { try FileManager.default.moveItem(at: source, to: target) }
    }

    static func copy(_ source: URL, to target: URL) throws(FileError) {
        try bridging(FileError.copyFailed, .fileWriteUnknown) { try FileManager.default.copyItem(at: source, to: target) }
    }

    /// Best effort: the system purges the temporary directory anyway.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Uploads

    static func read(_ url: URL) throws(FileError) -> Data {
        try bridging(FileError.readFailed, .fileReadUnknown) { try Data(contentsOf: url) }
    }

    static func read(_ url: URL, upTo limit: Int) throws(FileError) -> Data {
        try bridging(FileError.readFailed, .fileReadUnknown) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: limit) ?? Data()
        }
    }

    /// Best effort: the status already tells the failure, the body is only detail.
    static func errorBody(at url: URL) -> Data? {
        try? read(url, upTo: HTTPErrorBody<Void>.limit)
    }

    /// URLSession sends an empty body for a missing file, and the call would look successful.
    static func checkReadable(_ url: URL) throws(FileError) {
        let path = url.path(percentEncoded: false)
        guard !FileManager.default.isReadableFile(atPath: path) else { return }
        let code: CocoaError.Code = FileManager.default.fileExists(atPath: path) ? .fileReadNoPermission : .fileReadNoSuchFile
        throw .readFailed(CocoaError(code, userInfo: [NSFilePathErrorKey: path, NSURLErrorKey: url]))
    }
}
