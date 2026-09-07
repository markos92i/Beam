//
//  FileUtils.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation
import UniformTypeIdentifiers

public struct FileUtils {
    /// Derives a filename with proper extension from server-suggested name and content type.
    public static func resolveFilename(suggestedFilename: String?, contentType: String) -> String {
        if let suggested = suggestedFilename, !suggested.isEmpty {
            let suggestedURL = URL(fileURLWithPath: suggested)
            if suggestedURL.pathExtension.isEmpty {
                let ext = UTType(mimeType: contentType)?.preferredFilenameExtension
                    ?? String(contentType.split(separator: "/").last ?? "bin")
                return "\(suggested).\(ext)"
            }
            return suggested
        }
        let ext = UTType(mimeType: contentType)?.preferredFilenameExtension
            ?? String(contentType.split(separator: "/").last ?? "bin")
        return "\(UUID().uuidString).\(ext)"
    }

    /// Copies a file to the specified directory with an appropriate filename.
    public static func copy(
        url: URL,
        to directory: FileManager.SearchPathDirectory,
        suggestedFilename: String? = nil,
        contentType: String
    ) throws(FileError) -> URL {
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first
        let filename = resolveFilename(suggestedFilename: suggestedFilename, contentType: contentType)

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
