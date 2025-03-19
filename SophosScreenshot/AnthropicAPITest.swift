import Foundation
import SwiftUI
import SwiftAnthropic

// Debug version of AnthropicAPI for testing
class DebugAnthropicAPI: AnthropicAPI {
    // Override the private getAPIKey method for debugging
    @objc func debugGetAPIKey() -> String? {
        // Try from UserDefaults first in test mode
        if let key = UserDefaults.standard.string(forKey: "anthropic_api_key") {
            print("[DEBUG] Found API key in UserDefaults")
            return key
        }
        
        // Then try keychain
        return super.value(forKey: "getAPIKey") as? String
    }
    
    // Debug version of summarizeText with more logging
    func debugSummarizeText(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("[DEBUG] Starting summarization with \(text.count) characters of text")
        
        // Input validation
        guard !text.isEmpty else {
            print("[DEBUG] ERROR: Empty text input")
            completion(.failure(APIError.emptyInput))
            return
        }
        
        // Get API key
        guard let apiKey = debugGetAPIKey(), !apiKey.isEmpty else {
            print("[DEBUG] ERROR: API key is missing or empty")
            completion(.failure(APIError.missingAPIKey))
            return
        }
        
        print("[DEBUG] API Key found (masked): \(apiKey.prefix(4))...\(apiKey.suffix(4))")
        
        // Initialize service
        let service = AnthropicServiceFactory.service(apiKey: apiKey)
        print("[DEBUG] Initialized Anthropic service")
        
        // Create the message content with text only
        let content: MessageParameter.Message.Content = .text(
            "This is text extracted from a screenshot using OCR. Please summarize it concisely:\n\n\(text)"
        )
        
        // Create message parameter
        let messageParam = MessageParameter.Message(role: .user, content: content)
        let parameters = MessageParameter(
            model: Model.claude3Sonnet,
            messages: [messageParam],
            maxTokens: 1024
        )
        
        print("[DEBUG] Created request parameters using claude3Sonnet model")
        
        // Make the API request
        print("[DEBUG] Sending API request to Anthropic...")
        Task {
            do {
                print("[DEBUG] Awaiting API response...")
                let response = try await service.createMessage(parameters)
                
                print("[DEBUG] API response received: \(response)")
                
                // Extract the text content from the response
                if let content = response.content {
                    let summary = content.compactMap { block -> String? in
                        if case .text(let text) = block {
                            return text
                        }
                        return nil
                    }.joined(separator: "\n")
                    
                    print("[DEBUG] Summarization successful: \(summary.prefix(50))...")
                    DispatchQueue.main.async {
                        completion(.success(summary))
                    }
                } else {
                    print("[DEBUG] API ERROR: No content in response")
                    DispatchQueue.main.async {
                        completion(.failure(APIError.noData))
                    }
                }
            } catch {
                print("[DEBUG] API ERROR: \(error.localizedDescription)")
                print("[DEBUG] Error details: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

struct AnthropicAPITest: View {
    @State private var apiStatus: String = "Not tested"
    @State private var apiResponse: String = ""
    @State private var isLoading: Bool = false
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Anthropic API Test")
                .font(.headline)
            
            HStack {
                SecureField("Enter API Key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Save Key") {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty)
            }
            
            HStack {
                Button("Test API Key Retrieval") {
                    testAPIKeyRetrieval()
                }
                
                Button("Test Package") {
                    testPackageImport()
                }
                
                Button("Test Summarization") {
                    testSummarization()
                }
                .disabled(isLoading)
            }
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            Text("Status: \(apiStatus)")
                .foregroundColor(apiStatus.contains("SUCCESS") ? .green : (apiStatus.contains("ERROR") ? .red : .primary))
            
            ScrollView {
                VStack(alignment: .leading) {
                    Text("API Response:")
                        .font(.headline)
                    
                    Text(apiResponse)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
            }
            .frame(height: 200)
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func saveAPIKey() {
        // Save to UserDefaults for simple testing
        UserDefaults.standard.set(apiKey, forKey: "anthropic_api_key")
        apiStatus = "API key saved to UserDefaults"
        
        // Clear the field for security
        apiKey = ""
    }
    
    private func testAPIKeyRetrieval() {
        let debugAPI = DebugAnthropicAPI()
        
        if let apiKey = debugAPI.debugGetAPIKey(), !apiKey.isEmpty {
            let masked = apiKey.count > 8 ? String(apiKey.prefix(4)) + "..." + String(apiKey.suffix(4)) : "[Invalid key]"
            apiStatus = "SUCCESS: API key found: \(masked)"
        } else {
            apiStatus = "ERROR: API key not found or empty"
        }
    }
    
    private func testPackageImport() {
        apiStatus = "Testing SwiftAnthropic package..."
        
        // Test if basic SwiftAnthropic types can be created
        do {
            // Try creating basic Anthropic types
            let model = Model.claude3Sonnet
            let content: MessageParameter.Message.Content = .text("Hello")
            let messageParam = MessageParameter.Message(role: .user, content: content)
            let _ = MessageParameter(model: model, messages: [messageParam], maxTokens: 100)
            
            // Test service factory
            let dummyKey = "dummy_key_for_testing_only"
            let _ = AnthropicServiceFactory.service(apiKey: dummyKey)
            
            apiStatus = "SUCCESS: SwiftAnthropic package is properly imported"
            apiResponse = "Successfully created Model, MessageParameter, and AnthropicService instances"
        } catch {
            apiStatus = "ERROR: Failed to create SwiftAnthropic types"
            apiResponse = "Error: \(error)"
        }
    }
    
    private func testSummarization() {
        isLoading = true
        apiStatus = "Testing summarization..."
        
        let testText = """
        This is a test text for the Claude API.
        We're checking if the summarization functionality works correctly.
        If this works, you should see a summarized version of this text below.
        """
        
        let debugAPI = DebugAnthropicAPI()
        debugAPI.debugSummarizeText(testText) { result in
            isLoading = false
            
            switch result {
            case .success(let summary):
                apiStatus = "SUCCESS: Summarization completed"
                apiResponse = summary
            case .failure(let error):
                apiStatus = "ERROR: \(error.localizedDescription)"
                apiResponse = "Failed with error: \(error)"
            }
        }
    }
}

// Extension to help with calling private methods using reflection
extension NSObject {
    struct MethodSignature {
        let object: NSObject
        let selector: Selector
        
        func call(_ target: NSObject, _ args: Any...) -> Any? {
            let methodIMP = target.method(for: selector)?.implementation
            guard let method = methodIMP else { return nil }
            
            // Convert method implementation to a function pointer
            typealias MethodFunction = @convention(c) (NSObject, Selector, Any...) -> Any?
            let function = unsafeBitCast(method, to: MethodFunction.self)
            
            return function(target, selector, args)
        }
    }
    
    func method(for selector: Selector) -> MethodSignature? {
        guard responds(to: selector) else { return nil }
        return MethodSignature(object: self, selector: selector)
    }
}

// Preview provider for SwiftUI
struct AnthropicAPITest_Previews: PreviewProvider {
    static var previews: some View {
        AnthropicAPITest()
    }
}