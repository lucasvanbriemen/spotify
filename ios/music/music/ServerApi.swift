import Foundation

class SeverApi {
    private static let baseUrl: String = Secrets.base_url
    private static let apiKey: String = Secrets.api_key
    
    public static func get<T: Decodable>(endpoint: String) async throws -> T {
        return try await makeRequest(endpoint: endpoint)
    }
    
    private static func makeRequest<T: Decodable>(method: String = "GET", endpoint: String, data: Data? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseUrl)\(endpoint)")!)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
        
    }
}
