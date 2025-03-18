import SwiftUI
import Security

// KeychainManager for ContentView to store API key for future use
class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.sophos.screenshot"
    private let account = "anthropic_api_key"
    
    func saveAPIKey(_ apiKey: String) -> Bool {
        // First delete any existing key
        deleteAPIKey()
        
        let keyData = apiKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        // Also save to UserDefaults as a fallback for testing
        UserDefaults.standard.set(apiKey, forKey: "anthropic_api_key")
        print("API key saved to UserDefaults as fallback")
        
        return status == errSecSuccess
    }
    
    func getAPIKey() -> String? {
        print("Attempting to get API key from keychain")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        print("Keychain query status: \(status)")
        
        if status == errSecSuccess, let data = result as? Data {
            let apiKey = String(data: data, encoding: .utf8)
            print("API key found in keychain")
            return apiKey
        }
        
        // Try UserDefaults as fallback for testing
        if let fallbackKey = UserDefaults.standard.string(forKey: "anthropic_api_key") {
            print("Using fallback API key from UserDefaults")
            return fallbackKey
        }
        
        print("No API key found")
        return nil
    }
    
    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

struct ContentView: View {
    @State private var shortcutStatus = "Active"
    @State private var apiKey = ""
    @State private var showingAPIKeyField = false
    @State private var apiKeyStatus = ""
    @State private var isDescribingImages = UserDefaults.standard.bool(forKey: "useDescriptionAPI")
    
    private var savedAPIKey: String? {
        KeychainManager.shared.getAPIKey()
    }
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Screenshot Tool")
                .font(.headline)
            
            HStack {
                Image(systemName: "keyboard")
                    .foregroundColor(.green)
                Text("Global Shortcut: ⌘⇧8")
                    .font(.system(size: 14, weight: .semibold))
                Text("(\(shortcutStatus))")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            }
            .padding(.horizontal)
            
            Button("Take Screenshot") {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.screenshotManager.captureScreenSelection()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Divider()
            
            Toggle("Extract text with OCR (Claude API coming soon)", isOn: $isDescribingImages)
                .padding(.horizontal)
                .onChange(of: isDescribingImages) { describe in
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.screenshotManager.setUseDescriptionAPI(describe)
                    }
                    
                    // No API key needed for OCR
                }
            
            if isDescribingImages {
                // We'll keep the OCR functionality while allowing API key storage
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(savedAPIKey != nil ? .green : .gray)
                    Text("Anthropic API Key: " + (savedAPIKey != nil ? "Configured ✓" : "Not Set"))
                        .font(.caption)
                    Button(savedAPIKey != nil ? "Change" : "Set") {
                        showingAPIKeyField = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal)
                
                if showingAPIKeyField {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Anthropic API Key:")
                            .font(.caption)
                        
                        // Use a direct NSSecureTextField wrapper for better paste support
                        #if os(macOS)
                        PasteEnabledSecureField("Enter API Key", text: $apiKey)
                            .frame(height: 30)
                        #else
                        SecureField("Enter API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        #endif
                        
                        if !apiKeyStatus.isEmpty {
                            Text(apiKeyStatus)
                                .font(.caption)
                                .foregroundColor(apiKeyStatus.contains("saved") ? .green : .red)
                        }
                        
                        HStack {
                            Button("Save") {
                                if apiKey.isEmpty {
                                    apiKeyStatus = "API key cannot be empty"
                                } else {
                                    let success = KeychainManager.shared.saveAPIKey(apiKey)
                                    apiKeyStatus = success ? "API key saved securely" : "Failed to save API key"
                                    if success {
                                        apiKey = ""
                                        // Hide the field after a delay
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            showingAPIKeyField = false
                                            apiKeyStatus = ""
                                        }
                                    }
                                }
                            }
                            
                            Button("Cancel") {
                                apiKey = ""
                                apiKeyStatus = ""
                                showingAPIKeyField = false
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(isDescribingImages 
                     ? "OCR will extract text from your screenshots (API key saved for future use)"
                     : "Screenshots saved as base64 in JSON")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Files saved to Documents folder")
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(width: 300, height: 400)
        .padding()
        .onAppear {
            // Check if we need to show the API key field
            showingAPIKeyField = savedAPIKey == nil && isDescribingImages
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#if os(macOS)
// A custom SwiftUI wrapper around NSSecureTextField to properly support pasting
struct PasteEnabledSecureField: NSViewRepresentable {
    private var placeholder: String
    @Binding private var text: String
    
    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }
    
    func makeNSView(context: Context) -> NSSecureTextField {
        let secureField = NSSecureTextField()
        secureField.placeholderString = placeholder
        secureField.delegate = context.coordinator
        secureField.isBordered = true
        secureField.focusRingType = .exterior
        secureField.bezelStyle = .roundedBezel
        
        // Explicitly enable paste operations
        secureField.allowsEditingTextAttributes = true
        secureField.isEditable = true
        
        // Make sure the field can receive copy/paste commands
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        secureField.menu = menu
        
        // Set up key event monitoring to capture Command+V separately in case the standard
        // NSResponder chain doesn't handle it properly
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v",
               secureField.currentEditor() != nil {
                if let pasteString = NSPasteboard.general.string(forType: .string) {
                    secureField.stringValue = pasteString
                    context.coordinator.parent.text = pasteString
                }
                return nil // Consume the event
            }
            return event
        }
        
        return secureField
    }
    
    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasteEnabledSecureField
        
        init(_ parent: PasteEnabledSecureField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}
#endif