//
//  TransferStore.swift
//  Beam
//
//  The background transfers that finished with nobody awaiting them, kept on disk.
//

import Foundation

/// No lock: a record is written last and atomically, and taking or removing moves or deletes a whole folder.
struct TransferStore: Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// Application Support, because iOS empties `tmp` and Caches.
    init(sessionIdentifier: String) {
        let folder = sessionIdentifier.replacingOccurrences(of: "/", with: "_")
        self.init(root: URL.applicationSupportDirectory.appending(path: "Beam/Transfers/\(folder)", directoryHint: .isDirectory))
    }

    // MARK: - Record

    struct Record: Codable, Sendable {
        let v: Int
        let kind: Kind
        let taskDescription: String?
        let url: URL?
        let method: String?
        let status: Int?
        let headers: [String: String]?
        /// A name, never a path: the app's container moves when it is reinstalled or restored.
        let file: String?
        let failure: Failure?
        let finishedAt: Date
    }

    enum Kind: String, Codable, Sendable {
        case upload, download
    }

    enum Failure: Codable, Sendable {
        case network(code: Int)
        case storage
    }

    struct Entry: Sendable {
        let id: String
        let record: Record
    }

    // MARK: - Saving

    /// URLSession deletes `location` when the delegate callback returns. An error response is kept too.
    func save(_ location: URL, of task: URLSessionDownloadTask) -> BackgroundTransferResult {
        let response = task.response as? HTTPURLResponse
        let id = UUID().uuidString
        let folder = root.appending(path: id, directoryHint: .isDirectory)
        let name = FileUtils.resolveFilename(
            suggestedFilename: response?.suggestedFilename,
            contentType: response?.contentType ?? .data
        )

        do throws(FileError) {
            try prepare(folder)
            try FileUtils.move(location, to: folder.appending(path: name))
        } catch {
            // Recorded without a file, so the app still learns that it finished and failed.
            let recorded = (try? write(record(.download, of: task, file: nil, failure: .storage), to: folder)) != nil
            return BackgroundTransferResult(task: task, outcome: .failed(.file(error)), storeID: recorded ? id : nil)
        }
        return keep(.download, of: task, file: name, in: folder, id: id, outcome: .downloaded(folder.appending(path: name)))
    }

    /// Also an empty response: it still tells that the upload finished.
    func save(_ response: Data, ofUpload task: URLSessionTask) -> BackgroundTransferResult {
        let id = UUID().uuidString
        let folder = root.appending(path: id, directoryHint: .isDirectory)
        do throws(FileError) {
            try prepare(folder)
            try FileUtils.write(response, to: folder.appending(path: Self.responseName))
        } catch {
            return BackgroundTransferResult(task: task, outcome: .uploaded(response), storeID: nil)
        }
        return keep(.upload, of: task, file: Self.responseName, in: folder, id: id, outcome: .uploaded(response))
    }

    func saveFailure(of task: URLSessionTask, _ failure: URLError) -> BackgroundTransferResult {
        let id = UUID().uuidString
        let folder = root.appending(path: id, directoryHint: .isDirectory)
        let kind: Kind = task is URLSessionDownloadTask ? .download : .upload
        do throws(FileError) {
            try prepare(folder)
            try write(record(kind, of: task, file: nil, failure: .network(code: failure.errorCode)), to: folder)
            return BackgroundTransferResult(task: task, outcome: .failed(.network(failure)), storeID: id)
        } catch {
            return BackgroundTransferResult(task: task, outcome: .failed(.network(failure)), storeID: nil)
        }
    }

    private func keep(_ kind: Kind, of task: URLSessionTask, file: String, in folder: URL, id: String, outcome: BackgroundTransferResult.Outcome) -> BackgroundTransferResult {
        do throws(FileError) {
            try write(record(kind, of: task, file: file, failure: nil), to: folder)
            return BackgroundTransferResult(task: task, outcome: outcome, storeID: id)
        } catch {
            // Without its record nobody would find it later: only those listening now get it.
            return BackgroundTransferResult(task: task, outcome: outcome, storeID: nil)
        }
    }

    // MARK: - Reading

    func entries() -> [Entry] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { folder in
                let id = folder.lastPathComponent
                return (try? read(id)).map { Entry(id: id, record: $0) }
            }
            .sorted { $0.record.finishedAt < $1.record.finishedAt }
    }

    func result(of entry: Entry) -> BackgroundTransferResult {
        let record = entry.record
        let folder = root.appending(path: entry.id, directoryHint: .isDirectory)
        let outcome: BackgroundTransferResult.Outcome
        switch (record.kind, record.file, record.failure) {
        case (.download, let file?, _):
            outcome = .downloaded(folder.appending(path: file))
        case (.upload, let file?, _):
            do throws(FileError) {
                outcome = .uploaded(try FileUtils.read(folder.appending(path: file)))
            } catch {
                outcome = .failed(.file(error))
            }
        case (_, nil, .network(let code)?):
            outcome = .failed(.network(URLError(URLError.Code(rawValue: code))))
        case (_, nil, _):
            outcome = .failed(.file(.moveFailed(CocoaError(.fileWriteUnknown))))
        }
        return BackgroundTransferResult(
            request: record.url.map { url in
                var request = URLRequest(url: url)
                request.httpMethod = record.method
                return request
            },
            taskDescription: record.taskDescription,
            response: record.url.flatMap { url in
                record.status.flatMap { HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: record.headers) }
            },
            outcome: outcome,
            storeID: entry.id
        )
    }

    // MARK: - Taking and removing

    /// `nil` when there is none, or someone took or removed it first.
    func take(_ key: BackgroundTaskKey) -> BackgroundTransferResult? {
        guard let entry = entries().first(where: { BackgroundTaskDescription($0.record.taskDescription)?.key == key }) else {
            return nil
        }
        var taken = result(of: entry)
        if case .downloaded(let file) = taken.outcome {
            let claimed = FileUtils.temporaryLocation()
            do throws(FileError) { try FileUtils.move(file, to: claimed) } catch { return nil }
            taken.outcome = .downloaded(claimed)
        }
        remove(entry.id)
        taken.storeID = nil
        return taken
    }

    func remove(_ id: String) {
        FileUtils.discard(root.appending(path: id, directoryHint: .isDirectory))
    }

    func removeAll() {
        FileUtils.discard(root)
    }

    // MARK: - Files

    private static let recordName = "record.json"
    private static let responseName = "response"

    private func prepare(_ folder: URL) throws(FileError) {
        try FileUtils.createDirectory(folder)
        // A directory excluded from backup excludes its contents.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = self.root
        try FileUtils.bridging(FileError.writeFailed, .fileWriteUnknown) { try root.setResourceValues(values) }
    }

    private func record(_ kind: Kind, of task: URLSessionTask, file: String?, failure: Failure?) -> Record {
        let response = task.response as? HTTPURLResponse
        return Record(
            v: 1,
            kind: kind,
            taskDescription: task.taskDescription,
            url: task.originalRequest?.url,
            method: task.originalRequest?.httpMethod,
            status: response?.statusCode,
            headers: response?.allHeaderFields as? [String: String],
            file: file,
            failure: failure,
            finishedAt: Date()
        )
    }

    private func write(_ record: Record, to folder: URL) throws(FileError) {
        let data = try FileUtils.bridging(FileError.writeFailed, .fileWriteUnknown) { try JSONEncoder().encode(record) }
        try FileUtils.write(data, to: folder.appending(path: Self.recordName))
    }

    private func read(_ id: String) throws(FileError) -> Record {
        let data = try FileUtils.read(root.appending(path: id).appending(path: Self.recordName))
        return try FileUtils.bridging(FileError.readFailed, .fileReadCorruptFile) { try JSONDecoder().decode(Record.self, from: data) }
    }
}
