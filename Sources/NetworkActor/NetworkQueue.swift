//
//  NetworkQueue.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 19/9/24.
//

import Foundation

public actor NetworkQueue {
    private var queue: [URLSession] = []
    
    public func append(_ session: URLSession) async {
        queue.append(session)
    }
    
    public func contains(_ session: URLSession) async -> Bool {
        queue.contains(session)
    }
    
    public func remove(_ session: URLSession) async {
        queue.removeAll { $0 == session }
    }

    public func cancel(_ session: URLSession) async {
        session.invalidateAndCancel()
        await remove(session)
    }

    public func cancelAll() async {
        for session in queue { await cancel(session) }
    }
}
