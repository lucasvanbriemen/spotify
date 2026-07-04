import Foundation

class ServerApi {
    private static let baseUrl: String = Secrets.base_url
    private static let apiKey: String = Secrets.api_key
    
    public static func get<T: Decodable>(endpoint: String) async -> T? {
        return await makeRequest(endpoint: endpoint)
    }

    public static func post<T: Decodable>(endpoint: String, body: [String: Any]) async -> T? {
        let data = try? JSONSerialization.data(withJSONObject: body)
        return await makeRequest(method: "POST", endpoint: endpoint, data: data)
    }

    /// Fire-and-forget POST used for cache warmups (the "prepare" endpoints).
    /// The response carries no useful body, so it is ignored.
    public static func warm(endpoint: String) {
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request).resume()
    }

    private static func makeRequest<T: Decodable>(method: String = "GET", endpoint: String, data: Data? = nil) async -> T? {
        do {
            var request = URLRequest(url: URL(string: "\(baseUrl)\(endpoint)")!)
            request.httpMethod = method

            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let data {
                request.httpBody = data
            }

            let (responseData, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(T.self, from: responseData)
        } catch {
            print("server API failed \(error)")
            return nil
        }
    }
}
