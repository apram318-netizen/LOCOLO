//
//  EdgeFunctions.swift
//  Locolo
//
//  Builds requests to Supabase Edge Functions authorized with the signed-in
//  user's JWT, so functions can derive the caller from the token instead of
//  trusting ids in the request body.
//

import Foundation
import Supabase

enum EdgeFunctions {
    static func request(_ name: String, body: some Encodable) async throws -> URLRequest {
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/\(name)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = (try? await SupabaseManager.shared.client.auth.session.accessToken)
            ?? Secrets.supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}
