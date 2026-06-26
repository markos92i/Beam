//
//  FileUtils.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation
import UniformTypeIdentifiers

public struct FileUtils {
    /// Copies a file to the specified directory with an appropriate filename.
    ///
    /// - Parameters:
    ///   - url: Source file URL (typically the temporary URL from URLSession download).
    ///   - directory: Destination directory (e.g. `.cachesDirectory`).
    ///   - suggestedFilename: Filename suggested by the server (from `HTTPURLResponse.suggestedFilename`).
    ///     Falls back to a UUID-based name if nil or empty.
    ///   - contentType: MIME type used to derive file extension when `suggestedFilename` has none.
    /// - Returns: The destination URL where the file was copied.
    public static func copy(
        url: URL,
        to directory: FileManager.SearchPathDirectory,
        suggestedFilename: String? = nil,
        contentType: String
    ) throws(FileError) -> URL {
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first

        let filename: String
        if let suggested = suggestedFilename, !suggested.isEmpty {
            filename = suggested
        } else {
            let ext = UTType(mimeType: contentType)?.preferredFilenameExtension
                ?? String(contentType.split(separator: "/").last ?? "")
            filename = "\(UUID().uuidString).\(ext)"
        }

        guard let target = dir?.appendingPathComponent(filename) else {
            throw .invalidTargetURL
        }

        if FileManager.default.fileExists(atPath: target.path) {
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                throw .removeFailed(error)
            }
        }

        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            throw .copyFailed(error)
        }
    }
}
