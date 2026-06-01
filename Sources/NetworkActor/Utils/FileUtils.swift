//
//  FileUtils.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation
import UniformTypeIdentifiers

public struct FileUtils {
    public static func copy(
        url: URL,
        to directory: FileManager.SearchPathDirectory,
        contentType: String
    ) throws(FileError) -> URL {
        let dir = FileManager.default.urls(for: directory, in: .userDomainMask).first
        let sub = contentType.split(separator: "/").last
        let ext = UTType(mimeType: contentType)?.preferredFilenameExtension ?? String(sub ?? "")
        
        guard let target = dir?.appendingPathComponent("\(UUID().uuidString).\(ext)") else {
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
