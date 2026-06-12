//
//  RequestBuilderState.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 31/5/26.
//

import Foundation

public struct RequestBuilderState {
    var client: any ClientProtocol = Client(session: URLSession.shared)
    var auth: (any AuthProtocol)? = nil
    var crash: (any CrashProtocol)? = nil
    var serializer: any SerializerProtocol = Serializer()
    var config: ServiceConfig = .standard
    
    var method: HTTPMethod = .get
    var host: String = ""
    var path: String = ""
    var params: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: HTTPBody? = nil
    var timeout: TimeInterval = 60
    var cacheFile: String? = nil
}
