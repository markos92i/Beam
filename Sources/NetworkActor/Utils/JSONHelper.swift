//
//  JSONHelper.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 21/05/2026.
//

import Foundation

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
