import Foundation
import Security

class AnthropicAPI {
    static let shared = AnthropicAPI()
    
    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let model = "claude-3-7-sonnet-20250219"
    private let maxTokens = 1024
    private let apiVersion = "2023-06-01"
    
    private func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.sophos.screenshot",
            kSecAttrAccount as String: "anthropic_api_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    func describeImage(imageBase64: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let apiKey = getAPIKey(), !apiKey.isEmpty else {
            completion(.failure(APIError.missingAPIKey))
            return
        }
        
        // Create the request
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        
        // Prepare the message content with image
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/png",
                    "data": imageBase64
                ]
            ],
            [
                "type": "text",
                "text": "Describe this image in detail. What does it show?"
            ]
        ]
        
        // Create the request body
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        
        // Convert to JSON data
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Make the request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            do {
                // For debugging purposes
                let jsonStr = String(data: data, encoding: .utf8) ?? "Unable to convert to string"
                print("Raw API Response: \(jsonStr)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Extract the content from a successful response - newest Claude API format
                    if let message = json["content"] as? [[String: Any]] {
                        for item in message {
                            if let type = item["type"] as? String, type == "text",
                               let text = item["text"] as? String {
                                completion(.success(text))
                                return
                            }
                        }
                    }
                    
                    // Try to extract from standard API response
                    if let contentString = json["content"] as? String {
                        completion(.success(contentString))
                        return
                    }
                    
                    // Try newest format with direct text extraction
                    if let message = json["content"] as? [String: Any],
                       let text = message["text"] as? String {
                        completion(.success(text))
                        return
                    }
                    
                    // Try to get from Claude Messages API format
                    if let message = json["message"] as? [String: Any],
                       let content = message["content"] as? [[String: Any]] {
                        for item in content {
                            if let type = item["type"] as? String, type == "text",
                               let text = item["text"] as? String {
                                completion(.success(text))
                                return
                            }
                        }
                    }
                    
                    // Check for nested content in response format
                    if let message = json["message"] as? [String: Any],
                       let contentText = message["content"] as? String {
                        completion(.success(contentText))
                        return
                    }
                    
                    // Check in Claude format with nested content in messages array
                    if let messages = json["messages"] as? [[String: Any]] {
                        for message in messages {
                            if let role = message["role"] as? String, role == "assistant" {
                                if let content = message["content"] as? [[String: Any]] {
                                    for item in content {
                                        if let type = item["type"] as? String, type == "text",
                                           let text = item["text"] as? String {
                                            completion(.success(text))
                                            return
                                        }
                                    }
                                } else if let content = message["content"] as? String {
                                    completion(.success(content))
                                    return
                                }
                            }
                        }
                    }
                    
                    // Try direct extraction from various property paths
                    if let text = json["text"] as? String {
                        completion(.success(text))
                        return
                    }
                    
                    // Last resort - try to parse common patterns
                    if let textContent = try? self.extractTextContentFromResponse(json) {
                        completion(.success(textContent))
                        return
                    }
                    
                    // Pure fallback with debugging information
                    print("Unable to parse Claude response, raw JSON: \(jsonStr)")
                    completion(.success("I couldn't extract text from the image."))
                    return
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    private func extractTextContentFromResponse(_ json: [String: Any]) throws -> String {
        // Handle different potential response formats
        
        // Try to extract from content array
        if let content = json["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "text", 
                   let text = item["text"] as? String {
                    return text
                }
            }
        }
        
        // Try to extract from messages
        if let messages = json["messages"] as? [[String: Any]],
           let assistantMessage = messages.first(where: { ($0["role"] as? String) == "assistant" }),
           let content = assistantMessage["content"] as? String {
            return content
        }
        
        // Try to extract from legacy format
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        // Last resort - return the raw JSON as string
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let jsonString = String(data: data, encoding: .utf8) {
            return "Failed to parse response format. Raw response: \(jsonString)"
        }
        
        throw APIError.invalidResponse
    }
    
    enum APIError: Error {
        case missingAPIKey
        case noData
        case invalidResponse
        case parsingError
    }
}