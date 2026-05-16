//
//  NetworkQueue.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 19/9/24.
//

import Foundation

public actor NetworkQueue {
    private var tasks: [String: URLSessionTask] = [:]
    
    public func append(id: String, task: URLSessionTask) {
        tasks[id] = task
    }
    
    public func remove(id: String) {
        tasks.removeValue(forKey: id)
    }
    
    public func cancel(id: String) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
    }
    
    public func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
